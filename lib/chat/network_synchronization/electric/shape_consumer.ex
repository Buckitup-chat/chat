defmodule Chat.NetworkSynchronization.Electric.ShapeConsumer do
  @moduledoc """
  GenServer that consumes one Electric shape from one peer.

  Streams shape data via `Electric.Client` and writes changes to the local
  PostgreSQL database through `ShapeWriter`. Persists resume offsets via
  `OffsetStore` so the stream can resume after a restart.

  Runs the stream in a monitored `Task`. On task exit (network error, peer
  offline, etc.) it retries with exponential backoff (1s → 2s → 4s → max 5min).
  """

  use GenServer
  use Toolbox.OriginLog

  import Tools.GenServerHelpers

  alias Chat.NetworkSynchronization.Electric.OffsetStore
  alias Chat.NetworkSynchronization.Electric.Shapes
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.NetworkSynchronization.Status.ErrorStatus
  alias Chat.NetworkSynchronization.Status.LiveStatus
  alias Chat.NetworkSynchronization.Status.SynchronizingStatus
  alias Electric.Client.Message

  @initial_backoff_ms 1_000
  @max_backoff_ms 300_000

  # state: {peer_url, system_identifier, shape, task_info | nil, backoff_ms}
  # task_info: {pid, monitor_ref}

  def start_link(opts) do
    peer_url = Keyword.fetch!(opts, :peer_url)
    system_identifier = Keyword.fetch!(opts, :system_identifier)
    shape = Keyword.fetch!(opts, :shape)

    GenServer.start_link(
      __MODULE__,
      {peer_url, system_identifier, shape},
      Keyword.drop(opts, [:peer_url, :system_identifier, :shape])
    )
  end

  @impl true
  def init({peer_url, system_identifier, shape}) do
    {peer_url, system_identifier, shape, nil, @initial_backoff_ms, nil}
    |> ok_continue(:start_stream)
  end

  @impl true
  def handle_continue(
        :start_stream,
        {peer_url, system_identifier, shape, task_info, backoff, restart_ref}
      ) do
    {peer_url, system_identifier, shape, task_info, backoff, restart_ref}
    |> maybe_start_stream()
    |> noreply()
  end

  @impl true
  def handle_info(
        {:change, op, value},
        {peer_url, system_identifier, shape, task_info, backoff, restart_ref} = state
      ) do
    case ShapeWriter.write(shape, op, value) do
      {:ok, _} ->
        {peer_url, system_identifier, shape, task_info, backoff, restart_ref} |> noreply()

      {:error, :repo_not_available} ->
        state |> schedule_repo_retry(nil) |> noreply()

      {:error, {:repo_not_available, reason}} ->
        state |> schedule_repo_retry(reason) |> noreply()

      {:error, reason} ->
        log(
          "ShapeConsumer #{peer_url}/#{shape}: write failed (#{inspect(reason)}), skipping",
          :warning
        )

        {peer_url, system_identifier, shape, task_info, backoff, restart_ref} |> noreply()
    end
  end

  def handle_info(
        {:resume, resume_msg},
        {peer_url, system_identifier, shape, task_info, _backoff, restart_ref}
      ) do
    OffsetStore.save(system_identifier, shape, resume_msg)
    {peer_url, system_identifier, shape, task_info, @initial_backoff_ms, restart_ref} |> noreply()
  end

  def handle_info(
        :up_to_date,
        {peer_url, system_identifier, shape, task_info, _backoff, restart_ref}
      ) do
    broadcast_status(peer_url, shape, LiveStatus.new())
    {peer_url, system_identifier, shape, task_info, @initial_backoff_ms, restart_ref} |> noreply()
  end

  def handle_info(
        :must_refetch,
        {peer_url, system_identifier, shape, task_info, _backoff, restart_ref}
      ) do
    cancel_task(task_info)
    cancel_restart(restart_ref)
    OffsetStore.delete(system_identifier)

    {peer_url, system_identifier, shape, nil, @initial_backoff_ms, nil}
    |> maybe_start_stream()
    |> noreply()
  end

  def handle_info(
        :restart_stream,
        {peer_url, system_identifier, shape, nil, backoff, _restart_ref}
      ) do
    {peer_url, system_identifier, shape, nil, backoff, nil}
    |> maybe_start_stream()
    |> noreply()
  end

  def handle_info(:restart_stream, state) do
    state |> noreply()
  end

  # Current task exited — clear offset and schedule retry with exponential backoff.
  # Clearing the offset forces a full snapshot re-sync on restart, avoiding data gaps
  # when the replication stream drops (e.g., WAL sender timeout, PG restart).
  def handle_info(
        {:DOWN, ref, :process, _down_pid, reason},
        {peer_url, system_identifier, shape, {_task_pid, ref}, backoff, nil}
      ) do
    log(
      "ShapeConsumer #{peer_url}/#{shape}: stream exited (#{inspect(reason)}), clearing offset and retrying in #{backoff}ms",
      :warning
    )

    OffsetStore.delete(system_identifier, shape)
    broadcast_status(peer_url, shape, ErrorStatus.new(inspect(reason)))
    restart_ref = Process.send_after(self(), :restart_stream, backoff)
    next_backoff = min(backoff * 2, @max_backoff_ms)
    {peer_url, system_identifier, shape, nil, next_backoff, restart_ref} |> noreply()
  end

  # Stale :DOWN from a previously cancelled task — ignore
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    state |> noreply()
  end

  def handle_info(_msg, state), do: state |> noreply()

  @impl true
  def terminate(
        _reason,
        {_peer_url, _system_identifier, _shape, task_info, _backoff, restart_ref}
      ) do
    cancel_task(task_info)
    cancel_restart(restart_ref)
  end

  # Private

  defp launch_task(peer_url, system_identifier, shape) do
    resume = OffsetStore.load(system_identifier, shape)
    schema_module = Shapes.schema_module(shape)
    parent = self()

    stream_opts =
      [live: true, replica: :full]
      |> then(fn opts -> if resume, do: Keyword.put(opts, :resume, resume), else: opts end)

    {:ok, pid} =
      Task.start(fn ->
        Electric.Client.new!(
          endpoint: "#{peer_url}/electric/v1/#{shape}",
          fetch:
            {Electric.Client.Fetch.HTTP,
             request: [
               connect_options: [
                 transport_opts: [{:keepalive, true}]
               ]
             ]}
        )
        |> Electric.Client.stream(schema_module, stream_opts)
        |> Stream.each(&dispatch_message(&1, parent, peer_url, shape))
        |> Stream.run()
      end)

    ref = Process.monitor(pid)
    {pid, ref}
  end

  defp broadcast_status(peer_url, shape, status) do
    Phoenix.PubSub.broadcast(
      Chat.PubSub,
      Chat.NetworkSynchronization.notification_topic(),
      {:admin, {:electric_sync_status, peer_url, shape, status}}
    )
  end

  defp cancel_task(nil), do: :ok

  defp cancel_task({pid, ref}) do
    Process.demonitor(ref, [:flush])

    if Process.alive?(pid) do
      Process.exit(pid, :kill)
    end
  end

  defp cancel_restart(nil), do: :ok

  defp cancel_restart(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  defp maybe_start_stream({peer_url, system_identifier, shape, nil, backoff, _restart_ref}) do
    case Chat.Db.repo_ready?() do
      true ->
        broadcast_status(peer_url, shape, SynchronizingStatus.new())
        task_info = launch_task(peer_url, system_identifier, shape)
        {peer_url, system_identifier, shape, task_info, backoff, nil}

      false ->
        schedule_repo_retry({peer_url, system_identifier, shape, nil, backoff, nil}, nil)
    end
  end

  defp maybe_start_stream(state), do: state

  defp schedule_repo_retry(
         {peer_url, system_identifier, shape, task_info, backoff, nil},
         reason
       ) do
    detail =
      case format_reason(reason) do
        nil -> ""
        message -> " (#{message})"
      end

    log(
      "ShapeConsumer #{peer_url}/#{shape}: repo not available#{detail}, retrying in #{backoff}ms",
      :warning
    )

    cancel_task(task_info)
    broadcast_status(peer_url, shape, ErrorStatus.new("repo_not_available"))
    restart_ref = Process.send_after(self(), :restart_stream, backoff)
    next_backoff = min(backoff * 2, @max_backoff_ms)
    {peer_url, system_identifier, shape, nil, next_backoff, restart_ref}
  end

  defp schedule_repo_retry(
         {peer_url, system_identifier, shape, _task_info, backoff, restart_ref},
         _reason
       ) do
    {peer_url, system_identifier, shape, nil, backoff, restart_ref}
  end

  defp format_reason(nil), do: nil
  defp format_reason(%{message: message}) when is_binary(message), do: message
  defp format_reason(%{__exception__: true} = error), do: Exception.message(error)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp dispatch_message(message, parent, _url, _shape) do
    case message do
      %Message.ChangeMessage{headers: %{operation: op}, value: value} ->
        send(parent, {:change, op, value})

      %Message.ResumeMessage{} = resume ->
        send(parent, {:resume, resume})

      %Message.ControlMessage{control: :up_to_date} ->
        send(parent, :up_to_date)

      %Message.ControlMessage{control: :must_refetch} ->
        send(parent, :must_refetch)

      _ ->
        :ok
    end
  end
end
