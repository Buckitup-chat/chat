defmodule Chat.Data.File.GC do
  @moduledoc "Hourly garbage collection for deleted files and stale uploads."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.TimeKeeper

  @gc_interval :timer.hours(1)
  @stale_seconds 2 * 24 * 60 * 60
  @delete_timeout :timer.minutes(5)
  @chunk_batch_size 50

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @impl true
  def init(:ok) do
    schedule_gc()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:gc, state) do
    run_gc()
    schedule_gc()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_gc do
    Process.send_after(self(), :gc, @gc_interval)
  end

  defp run_gc do
    gc_deleted_files()
    gc_stale_uploads()
  rescue
    e ->
      log("GC failed: #{Exception.message(e)}", :warning)
  end

  defp gc_deleted_files do
    FileData.deleted_file_ids_with_chunks()
    |> Enum.each(fn file_id ->
      count = delete_chunks_in_batches(file_id)
      log("GC: deleted #{count} chunks from deleted file #{file_id}", :debug)
    end)
  end

  defp gc_stale_uploads do
    threshold = TimeKeeper.now_unix() - @stale_seconds

    FileData.stale_upload_chunk_file_ids(threshold)
    |> Enum.each(fn file_id ->
      {uc_count, _} = FileData.delete_upload_chunks_for_file(file_id)
      fc_count = delete_chunks_in_batches(file_id)

      log(
        "GC: pruned #{uc_count} upload_chunks and #{fc_count} orphan file_chunks from stale upload #{file_id}",
        :debug
      )
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
