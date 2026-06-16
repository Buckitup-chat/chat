defmodule Chat.Data.File.GC do
  @moduledoc "Hourly garbage collection for deleted files and stale uploads."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.ChunkStore
  alias Chat.Data.File.IpfsStore
  alias Chat.TimeKeeper

  @gc_interval :timer.hours(1)
  @stale_threshold :timer.hours(48)
  @delete_timeout :timer.minutes(5)
  @chunk_batch_size 50

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    schedule_gc()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:gc, state) do
    gc_deleted_files()
    gc_stale_uploads()
    gc_temp_files()
    schedule_gc()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # GC operations

  defp gc_deleted_files do
    FileData.deleted_file_ids_with_chunks()
    |> Enum.each(&purge_deleted_file/1)
  end

  defp purge_deleted_file(file_id) do
    delete_ipfs_blocks(file_id)
    count = delete_chunks_in_batches(file_id)
    FileData.delete_missing_chunks_for_file(file_id)
    ChunkStore.delete_file(file_id)
    log("GC: deleted #{count} chunks + store from deleted file #{file_id}", :debug)
  end

  defp gc_stale_uploads do
    (TimeKeeper.now_unix() - div(@stale_threshold, 1000))
    |> FileData.stale_upload_chunk_file_ids()
    |> Enum.each(&purge_stale_upload/1)
  end

  defp purge_stale_upload(file_id) do
    delete_ipfs_blocks(file_id)
    {uc_count, _} = FileData.delete_upload_chunks_for_file(file_id)
    fc_count = delete_chunks_in_batches(file_id)
    FileData.delete_missing_chunks_for_file(file_id)
    ChunkStore.delete_file(file_id)

    log(
      "GC: pruned #{uc_count} upload_chunks and #{fc_count} orphan file_chunks + store from stale upload #{file_id}",
      :debug
    )
  end

  defp gc_temp_files do
    ChunkStore.sweep_tmp_files(@gc_interval)
  end

  # Shared helpers

  defp schedule_gc do
    Process.send_after(self(), :gc, @gc_interval)
  end

  defp delete_ipfs_blocks(file_id) do
    FileData.get_file_chunks(file_id)
    |> Enum.each(fn
      %{cid: cid} when is_binary(cid) -> IpfsStore.delete(cid)
      _ -> :ok
    end)
  end

  defp delete_chunks_in_batches(file_id, total \\ 0) do
    {count, _} =
      FileData.delete_file_chunks_batch(file_id, @chunk_batch_size, timeout: @delete_timeout)

    case count do
      @chunk_batch_size -> delete_chunks_in_batches(file_id, total + count)
      _ -> total + count
    end
  end
end
