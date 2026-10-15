defmodule Chat.Data.File.ChunkPresence do
  @moduledoc "Reconciles file_chunks against missing_chunks: which chunks a drive holds and which it still lacks"

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.MissingChunk

  def present_chunk_keys(opts \\ []) do
    file_chunks_without_missing()
    |> select([fc, mc], {fc.file_id, fc.chunk_index})
    |> use_repo(opts).all()
  end

  def missing_chunk_keys(opts \\ []) do
    from(mc in MissingChunk, select: {mc.file_id, mc.chunk_index})
    |> use_repo(opts).all()
  end

  def backfill_missing_from_file_chunks(source_drive_id, now_unix, opts \\ []) do
    repo = use_repo(opts)

    file_chunks_without_missing()
    |> select([fc, mc], %{
      file_id: fc.file_id,
      chunk_index: fc.chunk_index,
      data_hash: fc.data_hash,
      size: fc.size
    })
    |> repo.all()
    |> Enum.chunk_every(200)
    |> Enum.reduce(0, fn batch, acc ->
      rows =
        Enum.map(batch, fn fc ->
          %{
            file_id: fc.file_id,
            chunk_index: fc.chunk_index,
            data_hash: fc.data_hash,
            size: fc.size,
            peer_url: nil,
            source_drive_id: source_drive_id,
            attempts: 0,
            updated_at: now_unix
          }
        end)

      {inserted, _} = repo.insert_all(MissingChunk, rows, on_conflict: :nothing)
      acc + inserted
    end)
  end

  defp file_chunks_without_missing do
    from(fc in FileChunk,
      left_join: mc in MissingChunk,
      on: mc.file_id == fc.file_id and mc.chunk_index == fc.chunk_index,
      where: not is_nil(fc.data_hash) and is_nil(mc.file_id)
    )
  end

  defp use_repo(opts) do
    case Keyword.get(opts, :repo) do
      nil -> repo()
      repo -> repo
    end
  end
end
