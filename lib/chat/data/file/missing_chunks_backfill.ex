defmodule Chat.Data.File.MissingChunksBackfill do
  @moduledoc "On pipeline start, backfills missing_chunks for file_chunks not present on disk."

  use Task, restart: :temporary
  use Toolbox.OriginLog

  import Ecto.Query

  alias Chat.Data.File.ChunkStore
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.TimeKeeper

  @batch_size 200

  def start_link(opts) do
    Task.start_link(__MODULE__, :run, [opts])
  end

  def run(opts) do
    repo = Keyword.get(opts, :repo) || Chat.Repo
    base_dir = Keyword.get(opts, :base_dir)
    now = TimeKeeper.now_unix()

    file_ids = active_file_ids(repo)
    count = backfill_files(file_ids, base_dir, now, repo)

    if count > 0, do: log("Backfilled #{count} missing_chunks entries", :info)
  end

  defp active_file_ids(repo) do
    from(f in "files", where: f.deleted_flag == false, select: f.file_id)
    |> repo.all()
  end

  defp backfill_files(file_ids, base_dir, now, repo) do
    Enum.reduce(file_ids, 0, fn file_id, total ->
      total + backfill_one_file(file_id, base_dir, now, repo)
    end)
  end

  defp backfill_one_file(file_id, base_dir, now, repo) do
    from(fc in "file_chunks",
      where: fc.file_id == ^file_id and not is_nil(fc.data_hash),
      select: %{chunk_index: fc.chunk_index, data_hash: fc.data_hash, size: fc.size}
    )
    |> repo.all()
    |> Enum.reject(fn fc -> chunk_on_disk?(file_id, fc.chunk_index, base_dir) end)
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(0, fn batch, acc ->
      {inserted, _} = insert_missing(file_id, batch, now, repo)
      acc + inserted
    end)
  end

  defp chunk_on_disk?(file_id, chunk_index, base_dir) do
    case ChunkStore.fetch(file_id, chunk_index, base_dir) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp insert_missing(file_id, batch, now, repo) do
    rows =
      Enum.map(batch, fn fc ->
        %{
          file_id: file_id,
          chunk_index: fc.chunk_index,
          data_hash: fc.data_hash,
          size: fc.size,
          peer_url: nil,
          source_drive_id: nil,
          attempts: 0,
          updated_at: now
        }
      end)

    repo.insert_all(MissingChunk, rows, on_conflict: :nothing)
  end
end
