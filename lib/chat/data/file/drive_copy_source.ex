defmodule Chat.Data.File.DriveCopySource do
  @moduledoc "Event-driven sink for drive-to-drive chunk copy. Reads from other drives' ChunkStores."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.ChunkStore
  alias Chat.Data.File.ChunkWriter
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.TimeKeeper

  @registry Chat.Data.File.ChunkPipelineRegistry
  @poll_interval :timer.hours(1)
  @batch_size 5
  @max_to_write 3
  @max_writing 2

  def start_link(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)
    GenServer.start_link(__MODULE__, opts, name: via(drive_id))
  end

  def chunk_fetchable(drive_id, file_id, chunk_index, source_drive_id) do
    GenServer.cast(via(drive_id), {:chunk_fetchable, file_id, chunk_index, source_drive_id})
  end

  def drive_mounted(drive_id, other_drive_id, base_dir) do
    GenServer.cast(via(drive_id), {:drive_mounted, other_drive_id, base_dir})
  end

  def drive_unmounted(drive_id, other_drive_id) do
    GenServer.cast(via(drive_id), {:drive_unmounted, other_drive_id})
  end

  @impl true
  def init(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)
    repo = Keyword.get(opts, :repo)
    Phoenix.PubSub.subscribe(Chat.PubSub, "chunk_pipeline")
    schedule_poll()

    state = %{
      drive_id: drive_id,
      repo: repo,
      other_drives: %{},
      sweep_timers: %{},
      to_fetch: :queue.new(),
      fetching: %{},
      to_write: :queue.new(),
      to_write_len: 0,
      writing: %{}
    }

    {:ok, state, {:continue, :initial_poll}}
  end

  @impl true
  def handle_continue(:initial_poll, state) do
    {:noreply, state |> enqueue_poll() |> drain()}
  end

  @impl true
  def handle_cast({:chunk_fetchable, file_id, chunk_index, source_drive_id}, state) do
    {:noreply, state |> enqueue(file_id, chunk_index, source_drive_id) |> drain()}
  end

  def handle_cast({:drive_mounted, other_drive_id, base_dir}, state) do
    if other_drive_id == state.drive_id do
      {:noreply, state}
    else
      others = Map.put(state.other_drives, other_drive_id, base_dir)
      timer_ref = Process.send_after(self(), {:sweep, other_drive_id}, 5_000)
      timers = Map.put(state.sweep_timers, other_drive_id, timer_ref)
      {:noreply, %{state | other_drives: others, sweep_timers: timers}}
    end
  end

  def handle_cast({:drive_unmounted, other_drive_id}, state) do
    others = Map.delete(state.other_drives, other_drive_id)
    {timer_ref, timers} = Map.pop(state.sweep_timers, other_drive_id)
    if timer_ref, do: Process.cancel_timer(timer_ref)
    {:noreply, %{state | other_drives: others, sweep_timers: timers}}
  end

  @impl true
  def handle_info(:poll, state) do
    schedule_poll()
    {:noreply, state |> enqueue_poll() |> drain()}
  end

  def handle_info({:sweep, other_drive_id}, state) do
    timers = Map.delete(state.sweep_timers, other_drive_id)
    state = %{state | sweep_timers: timers}

    state =
      if Map.has_key?(state.other_drives, other_drive_id),
        do: enqueue_sweep(state, other_drive_id),
        else: state

    {:noreply, drain(state)}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, state |> handle_task_result(ref, result) |> drain()}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    state =
      cond do
        Map.has_key?(state.fetching, ref) -> drop_fetch(state, ref)
        Map.has_key?(state.writing, ref) -> drop_write(state, ref)
        true -> state
      end

    {:noreply, drain(state)}
  end

  def handle_info({:chunk_pipeline, event}, state), do: handle_cast(event, state)

  def handle_info(_msg, state), do: {:noreply, state}

  defp drain(state) do
    state
    |> drain_writing()
    |> refill_if_idle()
    |> drain_fetching()
  end

  defp drain_writing(state) do
    if map_size(state.writing) < @max_writing and not :queue.is_empty(state.to_write) do
      {{:value, {file_id, chunk_index, body}}, to_write} = :queue.out(state.to_write)

      %{state | to_write: to_write, to_write_len: state.to_write_len - 1}
      |> start_write_task(file_id, chunk_index, body)
      |> drain_writing()
    else
      state
    end
  end

  defp refill_if_idle(state) do
    fetch_cap = 3 * (@max_to_write - state.to_write_len)

    if :queue.is_empty(state.to_fetch) and map_size(state.fetching) < fetch_cap,
      do: enqueue_poll(state),
      else: state
  end

  defp drain_fetching(state) do
    fetch_cap = 3 * (@max_to_write - state.to_write_len)

    if map_size(state.fetching) < fetch_cap and not :queue.is_empty(state.to_fetch) do
      {{:value, {file_id, chunk_index, source_drive_id}}, to_fetch} = :queue.out(state.to_fetch)

      %{state | to_fetch: to_fetch}
      |> start_fetch_task(file_id, chunk_index, source_drive_id)
      |> drain_fetching()
    else
      state
    end
  end

  defp handle_task_result(state, ref, result) do
    case result do
      {:fetched, file_id, chunk_index, body} ->
        pop_fetching(state, ref) |> enqueue_write(file_id, chunk_index, body)

      {:fetch_failed, file_id, chunk_index} ->
        record_failure(state, file_id, chunk_index)
        pop_fetching(state, ref)

      {:written, file_id, chunk_index} ->
        FileData.delete_missing_chunk(file_id, chunk_index, repo: state.repo)
        pop_writing(state, ref)

      {:write_failed, file_id, chunk_index} ->
        record_failure(state, file_id, chunk_index)
        pop_writing(state, ref)

      _ ->
        state
    end
  end

  defp pop_fetching(state, ref) do
    {_, fetching} = Map.pop(state.fetching, ref)
    %{state | fetching: fetching}
  end

  defp pop_writing(state, ref) do
    {_, writing} = Map.pop(state.writing, ref)
    %{state | writing: writing}
  end

  defp enqueue(state, file_id, chunk_index, source_drive_id) do
    %{state | to_fetch: :queue.in({file_id, chunk_index, source_drive_id}, state.to_fetch)}
  end

  defp enqueue_write(state, file_id, chunk_index, body) do
    %{
      state
      | to_write: :queue.in({file_id, chunk_index, body}, state.to_write),
        to_write_len: state.to_write_len + 1
    }
  end

  defp enqueue_poll(state) do
    if Chat.Db.repo_ready?(repo_module(state)) and map_size(state.other_drives) > 0 do
      in_pipeline = in_pipeline_keys(state)
      limit = MapSet.size(in_pipeline) + @batch_size

      FileData.fetchable_missing_chunks_for_copy(limit, nil, repo: state.repo)
      |> Enum.reject(fn mc -> MapSet.member?(in_pipeline, {mc.file_id, mc.chunk_index}) end)
      |> Enum.reduce(state, fn mc, acc ->
        enqueue(acc, mc.file_id, mc.chunk_index, mc.source_drive_id)
      end)
    else
      state
    end
  end

  defp in_pipeline_keys(state) do
    (Map.values(state.fetching) ++
       Map.values(state.writing) ++
       queue_keys(state.to_fetch) ++ queue_keys(state.to_write))
    |> MapSet.new()
  end

  defp queue_keys(q) do
    :queue.to_list(q) |> Enum.map(fn {fid, ci, _} -> {fid, ci} end)
  end

  defp enqueue_sweep(state, source_drive_id) do
    if Chat.Db.repo_ready?(repo_module(state)) do
      FileData.missing_chunks_for_drive(source_drive_id, repo: state.repo)
      |> Enum.reduce(state, fn mc, acc ->
        enqueue(acc, mc.file_id, mc.chunk_index, source_drive_id)
      end)
    else
      state
    end
  end

  defp start_fetch_task(state, file_id, chunk_index, source_drive_id) do
    %{repo: repo, other_drives: other_drives} = state

    task =
      Task.Supervisor.async_nolink(Chat.TaskSupervisor, fn ->
        source_dir = resolve_source_dir(other_drives, source_drive_id)

        with {:ok, body} <- ChunkStore.fetch(file_id, chunk_index, source_dir),
             :ok <- verify_hash(repo, file_id, chunk_index, body) do
          {:fetched, file_id, chunk_index, body}
        else
          {:error, reason} ->
            log("copy #{file_id}:#{chunk_index} failed: #{inspect(reason)}", :warning)
            {:fetch_failed, file_id, chunk_index}
        end
      end)

    %{state | fetching: Map.put(state.fetching, task.ref, {file_id, chunk_index})}
  end

  defp start_write_task(state, file_id, chunk_index, body) do
    %{drive_id: drive_id} = state
    meta = %{file_id: file_id, chunk_index: chunk_index}

    task =
      Task.Supervisor.async_nolink(Chat.TaskSupervisor, fn ->
        case ChunkWriter.submit(drive_id, :drive_copy, body, meta) do
          :ok -> {:written, file_id, chunk_index}
          {:error, _} -> {:write_failed, file_id, chunk_index}
        end
      end)

    %{state | writing: Map.put(state.writing, task.ref, {file_id, chunk_index})}
  end

  defp drop_fetch(state, ref) do
    {file_id, chunk_index} = Map.fetch!(state.fetching, ref)
    record_failure(state, file_id, chunk_index)
    pop_fetching(state, ref)
  end

  defp drop_write(state, ref) do
    {file_id, chunk_index} = Map.fetch!(state.writing, ref)
    record_failure(state, file_id, chunk_index)
    pop_writing(state, ref)
  end

  defp resolve_source_dir(other_drives, source_drive_id) when is_binary(source_drive_id) do
    Map.get(other_drives, source_drive_id) || pick_random_drive(other_drives)
  end

  defp resolve_source_dir(other_drives, _), do: pick_random_drive(other_drives)

  defp pick_random_drive(drives) when map_size(drives) == 0, do: nil

  defp pick_random_drive(drives) do
    drives |> Map.values() |> Enum.random()
  end

  defp verify_hash(repo, file_id, chunk_index, body) do
    expected = FileData.get_missing_chunk_hash(file_id, chunk_index, repo: repo)
    actual = body |> EnigmaPq.hash() |> FileChunkDataHash.from_binary()

    if actual == expected, do: :ok, else: {:error, :hash_mismatch}
  end

  defp record_failure(%{repo: repo}, file_id, chunk_index) do
    FileData.increment_missing_chunk_attempts(file_id, chunk_index, TimeKeeper.now_unix(),
      repo: repo
    )
  end

  defp repo_module(%{repo: nil}), do: Chat.Db.repo()
  defp repo_module(%{repo: repo}), do: repo

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)

  defp via(drive_id), do: {:via, Registry, {@registry, {:drive_copy_source, drive_id}}}
end
