defmodule Chat.Data.File.SyncSource do
  @moduledoc "Event-driven sink for network-synced chunks. Fetches from peers, submits to ChunkWriter."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.ChunkWriter
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.TimeKeeper

  @registry Chat.Data.File.ChunkPipelineRegistry
  @poll_interval :timer.hours(1)
  @batch_size 5
  @fetch_timeout :timer.seconds(60)
  @max_to_write 3
  @max_writing 2

  def start_link(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)
    GenServer.start_link(__MODULE__, opts, name: via(drive_id))
  end

  def chunk_fetchable(drive_id, file_id, chunk_index, peer_url) do
    GenServer.cast(via(drive_id), {:chunk_fetchable, file_id, chunk_index, peer_url})
  end

  def peer_connected(drive_id, peer_url) do
    GenServer.cast(via(drive_id), {:peer_connected, peer_url})
  end

  def peer_disconnected(drive_id, peer_url) do
    GenServer.cast(via(drive_id), {:peer_disconnected, peer_url})
  end

  @impl true
  def init(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)
    repo = Keyword.get(opts, :repo)
    schedule_poll()

    state = %{
      drive_id: drive_id,
      repo: repo,
      peers: MapSet.new(),
      sweep_timers: %{},
      to_fetch: :queue.new(),
      downloading: %{},
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
  def handle_cast({:chunk_fetchable, file_id, chunk_index, peer_url}, state) do
    {:noreply, state |> enqueue(file_id, chunk_index, peer_url) |> drain()}
  end

  def handle_cast({:peer_connected, peer_url}, state) do
    peers = MapSet.put(state.peers, peer_url)
    timer_ref = Process.send_after(self(), {:sweep, peer_url}, 5_000)
    timers = Map.put(state.sweep_timers, peer_url, timer_ref)
    {:noreply, %{state | peers: peers, sweep_timers: timers}}
  end

  def handle_cast({:peer_disconnected, peer_url}, state) do
    peers = MapSet.delete(state.peers, peer_url)

    timers =
      case Map.pop(state.sweep_timers, peer_url) do
        {nil, timers} -> timers
        {ref, timers} ->
          Process.cancel_timer(ref)
          timers
      end

    {:noreply, %{state | peers: peers, sweep_timers: timers}}
  end

  @impl true
  def handle_info(:poll, state) do
    schedule_poll()
    {:noreply, state |> enqueue_poll() |> drain()}
  end

  def handle_info({:sweep, peer_url}, state) do
    timers = Map.delete(state.sweep_timers, peer_url)
    state = %{state | sweep_timers: timers}

    state =
      if MapSet.member?(state.peers, peer_url),
        do: enqueue_sweep(state, peer_url),
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
        Map.has_key?(state.downloading, ref) -> drop_download(state, ref)
        Map.has_key?(state.writing, ref) -> drop_write(state, ref)
        true -> state
      end

    {:noreply, drain(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Pipeline

  defp drain(state) do
    state
    |> drain_writing()
    |> refill_if_idle()
    |> drain_downloading()
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
    download_cap = 3 * (@max_to_write - state.to_write_len)

    if :queue.is_empty(state.to_fetch) and map_size(state.downloading) < download_cap,
      do: enqueue_poll(state),
      else: state
  end

  defp drain_downloading(state) do
    download_cap = 3 * (@max_to_write - state.to_write_len)

    if map_size(state.downloading) < download_cap and not :queue.is_empty(state.to_fetch) do
      {{:value, {file_id, chunk_index, peer_url}}, to_fetch} = :queue.out(state.to_fetch)

      %{state | to_fetch: to_fetch}
      |> start_download_task(file_id, chunk_index, peer_url)
      |> drain_downloading()
    else
      state
    end
  end

  # Task results

  defp handle_task_result(state, ref, result) do
    case result do
      {:downloaded, file_id, chunk_index, body} ->
        {_meta, downloading} = Map.pop(state.downloading, ref)

        %{state | downloading: downloading}
        |> enqueue_write(file_id, chunk_index, body)

      {:download_failed, file_id, chunk_index} ->
        {_meta, downloading} = Map.pop(state.downloading, ref)
        record_failure(state, file_id, chunk_index)
        %{state | downloading: downloading}

      {:written, file_id, chunk_index} ->
        {_meta, writing} = Map.pop(state.writing, ref)
        FileData.delete_missing_chunk(file_id, chunk_index, repo: state.repo)
        %{state | writing: writing}

      {:write_failed, file_id, chunk_index} ->
        {_meta, writing} = Map.pop(state.writing, ref)
        record_failure(state, file_id, chunk_index)
        %{state | writing: writing}

      _ ->
        state
    end
  end

  # Enqueue

  defp enqueue(state, file_id, chunk_index, peer_url) do
    %{state | to_fetch: :queue.in({file_id, chunk_index, peer_url}, state.to_fetch)}
  end

  defp enqueue_write(state, file_id, chunk_index, body) do
    %{state |
      to_write: :queue.in({file_id, chunk_index, body}, state.to_write),
      to_write_len: state.to_write_len + 1}
  end

  defp enqueue_poll(state) do
    if Chat.Db.repo_ready?(repo_module(state)) do
      in_pipeline = in_pipeline_keys(state)
      limit = MapSet.size(in_pipeline) + @batch_size

      FileData.fetchable_missing_chunks_for_sync(limit, nil, repo: state.repo)
      |> Enum.reject(fn mc -> MapSet.member?(in_pipeline, {mc.file_id, mc.chunk_index}) end)
      |> Enum.reduce(state, fn mc, acc ->
        enqueue(acc, mc.file_id, mc.chunk_index, mc.peer_url)
      end)
    else
      state
    end
  end

  defp in_pipeline_keys(state) do
    download_keys = Map.values(state.downloading)
    writing_keys = Map.values(state.writing)
    fetch_keys = state.to_fetch |> :queue.to_list() |> Enum.map(fn {fid, ci, _} -> {fid, ci} end)
    write_keys = state.to_write |> :queue.to_list() |> Enum.map(fn {fid, ci, _} -> {fid, ci} end)

    MapSet.new(download_keys ++ writing_keys ++ fetch_keys ++ write_keys)
  end

  defp enqueue_sweep(state, peer_url) do
    if Chat.Db.repo_ready?(repo_module(state)) do
      FileData.missing_chunks_for_peer(peer_url, repo: state.repo)
      |> Enum.reduce(state, fn mc, acc ->
        enqueue(acc, mc.file_id, mc.chunk_index, peer_url)
      end)
    else
      state
    end
  end

  # Tasks

  defp start_download_task(state, file_id, chunk_index, peer_url) do
    %{repo: repo} = state

    task =
      Task.Supervisor.async_nolink(Chat.TaskSupervisor, fn ->
        with {:ok, body} <- fetch_chunk(peer_url, file_id, chunk_index),
             :ok <- verify_hash(repo, file_id, chunk_index, body) do
          {:downloaded, file_id, chunk_index, body}
        else
          {:error, reason} ->
            log("#{file_id}:#{chunk_index} fetch failed: #{inspect(reason)}", :warning)
            {:download_failed, file_id, chunk_index}
        end
      end)

    %{state | downloading: Map.put(state.downloading, task.ref, {file_id, chunk_index})}
  end

  defp start_write_task(state, file_id, chunk_index, body) do
    %{drive_id: drive_id} = state

    task =
      Task.Supervisor.async_nolink(Chat.TaskSupervisor, fn ->
        case ChunkWriter.submit(drive_id, :network_sync, body, %{
               file_id: file_id,
               chunk_index: chunk_index
             }) do
          :ok -> {:written, file_id, chunk_index}
          {:error, _} -> {:write_failed, file_id, chunk_index}
        end
      end)

    %{state | writing: Map.put(state.writing, task.ref, {file_id, chunk_index})}
  end

  defp drop_download(state, ref) do
    {{file_id, chunk_index}, downloading} = Map.pop(state.downloading, ref)
    record_failure(state, file_id, chunk_index)
    %{state | downloading: downloading}
  end

  defp drop_write(state, ref) do
    {{file_id, chunk_index}, writing} = Map.pop(state.writing, ref)
    record_failure(state, file_id, chunk_index)
    %{state | writing: writing}
  end

  # HTTP + verification

  defp fetch_chunk(peer_url, file_id, chunk_index) do
    url = "#{peer_url}/electric/v1/file_chunk/#{file_id}/#{chunk_index}"

    case Req.get(url, receive_timeout: @fetch_timeout) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
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

  defp via(drive_id), do: {:via, Registry, {@registry, {:sync_source, drive_id}}}
end
