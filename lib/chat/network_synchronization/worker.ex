defmodule Chat.NetworkSynchronization.Worker do
  @moduledoc "Worker"

  use GenServer

  import Chat.NetworkSynchronization, only: [monotonic_ms: 0]
  import Chat.NetworkSynchronization.Flow
  import Tools.GenServerHelpers


  @doc """
  ```elixir
    DynamicSupervisor.start_child(WorkerSupervisor, {Worker, source: network_source, deferred: true})
  ```
  """
  def start_link(opts) do
    source = Keyword.fetch!(opts, :source)
    deferred? = Keyword.get(opts, :deferred, false)

    GenServer.start_link(
      __MODULE__,
      {source, deferred?},
      opts |> Keyword.drop([:source, :deferred])
    )
  end

  @impl true
  def init({source, deferred?}) do
    if deferred? do
      {:ok, source, {:continue, :start_deferred}}
    else
      {:ok, source, {:continue, :start}}
    end
  end

  @impl true
  def handle_continue(:start, source) do
    send(self(), :synchronise)

    state(nil, source, [])
    |> noreply()
  end

  def handle_continue(:start_deferred, source) do
    source
    |> start_half_cooled()
    |> schedule_cooling_completed()
    |> state(source, [])
    |> noreply()
  end

  @impl true
  def handle_info(:synchronise, {source, _}) do
    start_synchronization(source,
      ok: fn status, keys ->
        status
        |> schedule_update()
        |> state(source, keys)
        |> noreply()
      end,
      error: fn status ->
        status
        |> schedule_retry()
        |> state(source, [])
        |> noreply()
      end
    )
  end

  def handle_info(:update, {source, _, []}) do
    source
    |> start_cooling()
    |> schedule_cooling_completed()
    |> state(source, [])
    |> noreply()
  end

  def handle_info(:update, {source, status, [remote_key, rest]}) do
    status
    |> start_key_retrieval(source, remote_key)
    |> schedule_update()
    |> state(source, rest)
    |> noreply()
  end

  defp schedule_update(x), do: tap(x, fn _ -> send(self(), :update) end)
  defp schedule_sync(x), do: tap(x, fn %{till: time} -> send_me_at(:synchronise, time) end)
  defp schedule_retry(x), do: schedule_sync(x)
  defp schedule_cooling_completed(x), do: schedule_sync(x)

  defp send_me_at(msg, mono_time) do
    Process.send_after(self(), msg, max(mono_time - monotonic_ms(), 0))
  end

  defp state(status, source, diff), do: {source, status, diff}
end
