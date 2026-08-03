defmodule Chat.Debug do
  @moduledoc """
  IEx-only helpers for inspecting and resetting pq_files storage
  (Postgres manifests/chunks + filesystem ChunkStore) on a live device.
  """

  import Ecto.Query

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.ChunkStore
  alias Chat.Data.File.DriveCopySource
  alias Chat.Data.File.SyncSource
  alias Chat.Data.Schemas.File, as: FileSchema
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Data.Schemas.UploadChunk
  alias Chat.Db.Common
  alias Chat.Repo
  alias Chat.TimeKeeper

  @registry Chat.Data.File.ChunkPipelineRegistry

  # Mirrors Chat.Data.File's retry-cooldown thresholds, so a missing_chunks
  # row here can be judged "backed off" vs "eligible for its next attempt".
  @cooldown_attempts 5
  @cooldown_seconds 900

  @doc "Deletes all pq_files data: files/file_chunks/upload_chunks/missing_chunks rows and the on-disk chunk tree."
  def reset_pq_files! do
    Repo.query!("TRUNCATE files, file_chunks, upload_chunks, missing_chunks")

    Common.get_chat_db_env(:files_base_dir)
    |> Path.join("pq_files")
    |> File.rm_rf!()

    :ok
  end

  @doc "Reports DB (manifest/chunks/uploads/missing) and filesystem state for a single file_id."
  def pq_file_status(file_id) do
    %{
      manifest: FileData.get_file(file_id),
      file_chunks: FileData.get_file_chunk_count(file_id),
      upload_chunks: upload_chunk_count(file_id),
      missing_chunks: FileData.missing_chunk_count(file_id),
      chunks_on_disk: chunks_on_disk(file_id)
    }
  end

  @doc """
  Walks the drive-copy decision chain for one file_id across every live drive
  pipeline: manifest -> replicated file_chunks metadata -> missing_chunks
  queue (with retry/cooldown status) -> bytes on disk, plus the live
  ReplicationListener/DriveCopySource/SyncSource/ChunkWriter process state
  that decides whether a missing chunk can be fetched right now. Returns a
  map keyed by drive_id.
  """
  def pq_file_chain(file_id) do
    for drive_id <- drive_ids(), into: %{}, do: {drive_id, drive_chain(drive_id, file_id)}
  end

  @doc "Dumps the Postgres missing_chunks drive-copy queue for every live drive (internal + each mounted USB)."
  def pq_drive_queues do
    @registry
    |> Registry.select([{{{:replication_listener, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Map.new(fn {drive_id, pid} -> {drive_id, drive_missing_chunks(pid)} end)
  end

  defp drive_missing_chunks(pid) do
    repo = pid |> :sys.get_state() |> Map.fetch!(:repo)

    from(m in MissingChunk, order_by: [asc: m.file_id, asc: m.chunk_index])
    |> repo.all()
  end

  defp upload_chunk_count(file_id) do
    from(u in UploadChunk, where: u.file_id == ^file_id, select: count())
    |> Repo.one()
  end

  defp chunks_on_disk(file_id, base_dir \\ nil) do
    file_id
    |> ChunkStore.file_dir(base_dir)
    |> File.ls()
    |> case do
      {:ok, entries} -> Enum.sort(entries)
      {:error, reason} -> {:error, reason}
    end
  end

  # --- pq_file_chain ---

  defp drive_ids do
    @registry
    |> Registry.select([{{{:replication_listener, :"$1"}, :_, :_}, [], [:"$1"]}])
  end

  defp drive_chain(drive_id, file_id) do
    listener_pid = registry_pid(:replication_listener, drive_id)
    listener_state = listener_pid && :sys.get_state(listener_pid)
    repo = listener_state && listener_state.repo

    writer_pid = registry_pid(:writer, drive_id)
    writer_state = writer_pid && :sys.get_state(writer_pid)

    %{
      manifest: repo && repo.get(FileSchema, file_id),
      replicated_chunk_indices: repo && file_chunk_indices(repo, file_id),
      missing_chunks: repo && missing_chunks_with_status(repo, file_id),
      chunks_on_disk: writer_state && chunks_on_disk(file_id, writer_state.base_dir),
      replication_listener: listener_status(listener_state),
      drive_copy_source: drive_copy_status(registry_pid(:drive_copy_source, drive_id), file_id),
      sync_source: sync_status(registry_pid(:sync_source, drive_id), file_id),
      writer: writer_status(writer_state, file_id)
    }
  end

  defp registry_pid(tag, drive_id) do
    case Registry.lookup(@registry, {tag, drive_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp file_chunk_indices(repo, file_id) do
    from(c in FileChunk,
      where: c.file_id == ^file_id,
      order_by: c.chunk_index,
      select: c.chunk_index
    )
    |> repo.all()
  end

  defp missing_chunks_with_status(repo, file_id) do
    now = TimeKeeper.now_unix()

    from(m in MissingChunk, where: m.file_id == ^file_id, order_by: m.chunk_index)
    |> repo.all()
    |> Enum.map(&annotate_missing_chunk(&1, now))
  end

  defp annotate_missing_chunk(chunk, now) do
    %{
      chunk_index: chunk.chunk_index,
      metadata_known?: not is_nil(chunk.data_hash),
      attempts: chunk.attempts,
      seconds_since_update: now - chunk.updated_at,
      in_cooldown?:
        chunk.attempts >= @cooldown_attempts and now - chunk.updated_at < @cooldown_seconds,
      peer_url: chunk.peer_url,
      source_drive_id: chunk.source_drive_id
    }
  end

  defp listener_status(nil), do: %{registered?: false}

  defp listener_status(state) do
    %{registered?: true, connected?: not is_nil(state.conn), system_id: state.system_id}
  end

  defp drive_copy_status(nil, _file_id), do: %{registered?: false}

  defp drive_copy_status(pid, file_id) do
    state = :sys.get_state(pid)

    %{
      registered?: true,
      known_drives: Map.keys(state.other_drives),
      can_poll?: DriveCopySource.can_poll?(state)
    }
    |> Map.merge(source_queues(state, file_id))
  end

  defp sync_status(nil, _file_id), do: %{registered?: false}

  defp sync_status(pid, file_id) do
    state = :sys.get_state(pid)

    %{
      registered?: true,
      known_peers: MapSet.to_list(state.peers),
      can_poll?: SyncSource.can_poll?(state)
    }
    |> Map.merge(source_queues(state, file_id))
  end

  defp source_queues(state, file_id) do
    %{
      queued_to_fetch: queue_for_file(state.to_fetch, file_id),
      fetching: tracked_for_file(state.fetching, file_id),
      queued_to_write: write_queue_for_file(state.to_write, file_id),
      writing: tracked_for_file(state.writing, file_id)
    }
  end

  defp queue_for_file(queue, file_id) do
    queue
    |> :queue.to_list()
    |> Enum.filter(fn {fid, _idx, _source} -> fid == file_id end)
    |> Enum.map(fn {_fid, idx, source} -> %{chunk_index: idx, source: source} end)
  end

  defp write_queue_for_file(queue, file_id) do
    queue
    |> :queue.to_list()
    |> Enum.filter(fn {fid, _idx, _body} -> fid == file_id end)
    |> Enum.map(fn {_fid, idx, body} -> %{chunk_index: idx, bytes: byte_size(body)} end)
  end

  defp tracked_for_file(refs, file_id) do
    refs
    |> Map.values()
    |> Enum.filter(fn {fid, _idx} -> fid == file_id end)
    |> Enum.map(fn {_fid, idx} -> idx end)
  end

  defp writer_status(nil, _file_id), do: %{registered?: false}

  defp writer_status(state, file_id) do
    %{
      registered?: true,
      queue_lengths: Map.new(state.queues, fn {lane, q} -> {lane, :queue.len(q)} end),
      wait_counters: state.wait_counters,
      queued_for_file: queued_chunks_for_file(state.queues, file_id)
    }
  end

  defp queued_chunks_for_file(queues, file_id) do
    for {lane, q} <- queues,
        {_from, _data, meta} <- :queue.to_list(q),
        meta.file_id == file_id do
      %{lane: lane, chunk_index: meta.chunk_index}
    end
  end
end
