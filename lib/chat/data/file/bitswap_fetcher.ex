defmodule Chat.Data.File.BitswapFetcher do
  @moduledoc "Event-driven chunk fetcher via IPFS Bitswap. Replaces HTTP polling for CID-bearing chunks."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.IpfsStore
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.TimeKeeper

  @max_concurrent Application.compile_env(:chat, :bitswap_max_concurrent, 5)
  @fetch_timeout :timer.minutes(5)
  @bootstrap_delay :timer.seconds(10)
  @bootstrap_batch 100

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  def request_fetch(file_id, chunk_index, cid, data_hash) do
    GenServer.cast(__MODULE__, {:request, file_id, chunk_index, cid, data_hash})
  end

  @impl true
  def init(:ok) do
    Process.send_after(self(), :bootstrap, @bootstrap_delay)
    {:ok, %{queue: :queue.new(), in_flight: MapSet.new(), task_refs: %{}}}
  end

  @impl true
  def handle_cast({:request, file_id, chunk_index, cid, data_hash}, state) do
    key = {file_id, chunk_index}

    state =
      if MapSet.member?(state.in_flight, key) or queued?(state.queue, key) do
        state
      else
        state
        |> Map.update!(:queue, &:queue.in(&1, {file_id, chunk_index, cid, data_hash}))
        |> maybe_dispatch()
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, {:ok, file_id, chunk_index, body}}, state) do
    Process.demonitor(ref, [:flush])
    handle_success(file_id, chunk_index, body)
    {:noreply, finish_task(ref, state)}
  end

  @impl true
  def handle_info({ref, {:error, file_id, chunk_index, reason}}, state) do
    Process.demonitor(ref, [:flush])
    log("Bitswap fetch failed #{file_id}:#{chunk_index}: #{inspect(reason)}", :warning)
    bump_attempts(file_id, chunk_index)
    {:noreply, finish_task(ref, state)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.get(state.task_refs, ref) do
      {file_id, chunk_index} ->
        log("Bitswap task crashed #{file_id}:#{chunk_index}: #{inspect(reason)}", :warning)
        bump_attempts(file_id, chunk_index)
        {:noreply, finish_task(ref, state)}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:bootstrap, state) do
    state =
      if Chat.Db.repo_ready?() do
        FileData.bitswap_fetchable_missing_chunks(@bootstrap_batch)
        |> Enum.reduce(state, fn mc, acc ->
          key = {mc.file_id, mc.chunk_index}

          if MapSet.member?(acc.in_flight, key) or queued?(acc.queue, key) do
            acc
          else
            Map.update!(
              acc,
              :queue,
              &:queue.in(&1, {mc.file_id, mc.chunk_index, mc.cid, mc.data_hash})
            )
          end
        end)
        |> maybe_dispatch()
      else
        Process.send_after(self(), :bootstrap, @bootstrap_delay)
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp maybe_dispatch(state) do
    if MapSet.size(state.in_flight) < @max_concurrent and not :queue.is_empty(state.queue) do
      {{:value, {file_id, chunk_index, cid, _data_hash}}, queue} = :queue.out(state.queue)
      key = {file_id, chunk_index}

      task =
        Task.Supervisor.async_nolink(Chat.BitswapTaskSupervisor, fn ->
          case IpfsStore.get(cid, receive_timeout: @fetch_timeout) do
            {:ok, body} -> {:ok, file_id, chunk_index, body}
            {:error, reason} -> {:error, file_id, chunk_index, reason}
          end
        end)

      %{
        state
        | queue: queue,
          in_flight: MapSet.put(state.in_flight, key),
          task_refs: Map.put(state.task_refs, task.ref, key)
      }
      |> maybe_dispatch()
    else
      state
    end
  end

  defp finish_task(ref, state) do
    {key, task_refs} = Map.pop(state.task_refs, ref)

    %{state | in_flight: MapSet.delete(state.in_flight, key), task_refs: task_refs}
    |> maybe_dispatch()
  end

  defp handle_success(file_id, chunk_index, body) do
    actual_hash = body |> EnigmaPq.hash() |> FileChunkDataHash.from_binary()

    case FileData.get_missing_chunk(file_id, chunk_index) do
      %{data_hash: ^actual_hash} ->
        FileData.delete_missing_chunk(file_id, chunk_index)
        log("Bitswap admitted #{file_id}:#{chunk_index}", :debug)

      %{data_hash: expected} ->
        log("Bitswap hash mismatch #{file_id}:#{chunk_index}: expected #{expected}", :warning)
        bump_attempts(file_id, chunk_index)

      nil ->
        :ok
    end
  end

  defp bump_attempts(file_id, chunk_index) do
    FileData.increment_missing_chunk_attempts(file_id, chunk_index, TimeKeeper.now_unix())
  end

  defp queued?(queue, key) do
    :queue.any(fn {fid, ci, _, _} -> {fid, ci} == key end, queue)
  end
end
