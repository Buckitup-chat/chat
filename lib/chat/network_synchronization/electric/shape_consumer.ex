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

  require Logger

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
    {peer_url, system_identifier, shape, nil, @initial_backoff_ms}
    |> ok_continue(:start_stream)
  end

  @impl true
  def handle_continue(:start_stream, {peer_url, system_identifier, shape, _task_info, backoff}) do
    broadcast_status(peer_url, shape, SynchronizingStatus.new())
    task_info = launch_task(peer_url, system_identifier, shape)
    {peer_url, system_identifier, shape, task_info, backoff} |> noreply()
  end

  @impl true
  def handle_info({:change, op, value}, {peer_url, system_identifier, shape, task_info, backoff}) do
    ShapeWriter.write(shape, op, value)
    {peer_url, system_identifier, shape, task_info, backoff} |> noreply()
  end

  def handle_info(
        {:resume, resume_msg},
        {peer_url, system_identifier, shape, task_info, _backoff}
      ) do
    OffsetStore.save(system_identifier, shape, resume_msg)
    {peer_url, system_identifier, shape, task_info, @initial_backoff_ms} |> noreply()
  end

  def handle_info(:up_to_date, {peer_url, system_identifier, shape, task_info, _backoff}) do
    broadcast_status(peer_url, shape, LiveStatus.new())
    {peer_url, system_identifier, shape, task_info, @initial_backoff_ms} |> noreply()
  end

  def handle_info(:must_refetch, {peer_url, system_identifier, shape, task_info, _backoff}) do
    cancel_task(task_info)
    OffsetStore.delete(system_identifier)
    broadcast_status(peer_url, shape, SynchronizingStatus.new())
    new_task_info = launch_task(peer_url, system_identifier, shape)
    {peer_url, system_identifier, shape, new_task_info, @initial_backoff_ms} |> noreply()
  end

  def handle_info(:restart_stream, {peer_url, system_identifier, shape, _task_info, backoff}) do
    task_info = launch_task(peer_url, system_identifier, shape)
    {peer_url, system_identifier, shape, task_info, backoff} |> noreply()
  end

  # Current task exited — schedule retry with exponential backoff
  def handle_info(
        {:DOWN, ref, :process, _down_pid, reason},
        {peer_url, system_identifier, shape, {_task_pid, ref}, backoff}
      ) do
    Logger.warning(
      "ShapeConsumer #{peer_url}/#{shape}: stream exited (#{inspect(reason)}), retrying in #{backoff}ms"
    )

    broadcast_status(peer_url, shape, ErrorStatus.new(inspect(reason)))
    Process.send_after(self(), :restart_stream, backoff)
    next_backoff = min(backoff * 2, @max_backoff_ms)
    {peer_url, system_identifier, shape, nil, next_backoff} |> noreply()
  end

  # Stale :DOWN from a previously cancelled task — ignore
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    state |> noreply()
  end

  def handle_info(_msg, state), do: state |> noreply()

  @impl true
  def terminate(_reason, {_peer_url, _system_identifier, _shape, task_info, _backoff}) do
    cancel_task(task_info)
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
        Electric.Client.new!(endpoint: "#{peer_url}/electric/v1/#{shape}")
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
    Process.exit(pid, :kill)
  end

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
