defmodule Chat.Data.File.GC do
  @moduledoc "Hourly garbage collection for deleted files and stale uploads."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.TimeKeeper

  @gc_interval :timer.hours(1)
  @stale_seconds 2 * 24 * 60 * 60

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
    file_ids = FileData.deleted_file_ids()

    case file_ids do
      [] ->
        :ok

      ids ->
        {count, _} = FileData.delete_file_chunks_for_files(ids)
        log("GC: deleted #{count} chunks from #{length(ids)} deleted files", :debug)
    end
  end

  defp gc_stale_uploads do
    threshold = TimeKeeper.now_unix() - @stale_seconds
    file_ids = FileData.stale_upload_chunk_file_ids(threshold)

    case file_ids do
      [] ->
        :ok

      ids ->
        {uc_count, _} = FileData.delete_upload_chunks_for_files(ids)
        {fc_count, _} = FileData.delete_file_chunks_for_files(ids)

        log(
          "GC: pruned #{uc_count} upload_chunks and #{fc_count} orphan file_chunks from #{length(ids)} stale uploads",
          :debug
        )
    end
  end
end
