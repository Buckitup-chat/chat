defmodule Chat.Data.File do
  @moduledoc "File context for managing file storage data in Postgres"

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.File
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Data.Schemas.UploadChunk

  def get_file(file_id) do
    repo().get(File, file_id)
  end

  def get_file_chunk(file_id, chunk_index) do
    repo().get_by(FileChunk, file_id: file_id, chunk_index: chunk_index)
  end

  def get_file_chunks(file_id) do
    from(c in FileChunk, where: c.file_id == ^file_id)
    |> repo().all()
  end

  def get_file_chunk_count(file_id) do
    from(c in FileChunk, where: c.file_id == ^file_id, select: count())
    |> repo().one()
  end

  def upsert_file(changeset) do
    repo().insert(changeset,
      on_conflict: file_upsert_query(),
      conflict_target: :file_id,
      allow_stale: true
    )
  end

  defp file_upsert_query do
    from(f in File,
      update: [
        set: [
          total_size: fragment("EXCLUDED.total_size"),
          chunk_size: fragment("EXCLUDED.chunk_size"),
          chunk_count: fragment("EXCLUDED.chunk_count"),
          chunk_sign_hashes: fragment("EXCLUDED.chunk_sign_hashes"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64")
        ]
      ],
      where:
        is_nil(f.owner_timestamp) or
          f.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end

  def update_file(%File{} = existing, %File{} = new_file) do
    existing
    |> File.delete_changeset(Map.from_struct(new_file))
    |> repo().update()
  end

  def insert_file_chunk(changeset) do
    repo().insert(changeset,
      on_conflict: :nothing,
      conflict_target: [:file_id, :chunk_index]
    )
  end

  def update_file_chunk_cid(file_id, chunk_index, cid) do
    from(c in FileChunk,
      where: c.file_id == ^file_id and c.chunk_index == ^chunk_index
    )
    |> repo().update_all(set: [cid: cid])
  end

  def insert_upload_chunk(attrs) do
    %UploadChunk{}
    |> UploadChunk.create_changeset(attrs)
    |> repo().insert(
      on_conflict: :nothing,
      conflict_target: [:file_id, :chunk_index]
    )
  end

  def delete_upload_chunks_for_file(file_id) do
    from(u in UploadChunk, where: u.file_id == ^file_id)
    |> repo().delete_all()
  end

  def delete_file_chunks_batch(file_id, limit, opts \\ []) do
    batch =
      from(c in FileChunk,
        where: c.file_id == ^file_id,
        limit: ^limit,
        select: c.chunk_index
      )

    from(c in FileChunk,
      where: c.file_id == ^file_id,
      where: c.chunk_index in subquery(batch)
    )
    |> repo().delete_all(opts)
  end

  def deleted_file_ids_with_chunks do
    chunk_file_ids = from(c in FileChunk, distinct: true, select: c.file_id)

    from(f in File,
      where: f.deleted_flag == true,
      where: f.file_id in subquery(chunk_file_ids),
      select: f.file_id
    )
    |> repo().all()
  end

  def stale_upload_chunk_file_ids(threshold_unix) do
    committed_file_ids = from(f in File, select: f.file_id)

    from(u in UploadChunk,
      where: u.updated_at < ^threshold_unix,
      where: u.file_id not in subquery(committed_file_ids),
      distinct: u.file_id,
      select: u.file_id
    )
    |> repo().all()
  end

  def delete_upload_chunks_for_files(file_ids) do
    from(u in UploadChunk, where: u.file_id in ^file_ids)
    |> repo().delete_all()
  end

  def delete_file_chunks_for_files(file_ids) do
    from(c in FileChunk, where: c.file_id in ^file_ids)
    |> repo().delete_all()
  end

  # --- MissingChunks ---

  def insert_missing_chunks_placeholders(file_id, chunk_count, peer_url, now_unix) do
    rows =
      for idx <- 0..(chunk_count - 1) do
        %{
          file_id: file_id,
          chunk_index: idx,
          data_hash: nil,
          size: nil,
          peer_url: peer_url,
          attempts: 0,
          updated_at: now_unix
        }
      end

    repo().insert_all(MissingChunk, rows, on_conflict: :nothing)
  end

  def fill_missing_chunk(file_id, chunk_index, data_hash, size, cid) do
    from(m in MissingChunk,
      where: m.file_id == ^file_id and m.chunk_index == ^chunk_index
    )
    |> repo().update_all(set: [data_hash: data_hash, size: size, cid: cid])
  end

  def delete_missing_chunk(file_id, chunk_index) do
    from(m in MissingChunk,
      where: m.file_id == ^file_id and m.chunk_index == ^chunk_index
    )
    |> repo().delete_all()
  end

  def delete_missing_chunks_for_file(file_id) do
    from(m in MissingChunk, where: m.file_id == ^file_id)
    |> repo().delete_all()
  end

  def fetchable_missing_chunks(limit) do
    from(m in MissingChunk,
      where: not is_nil(m.data_hash),
      order_by: [
        asc: fragment("CASE WHEN ? IS NULL THEN 0 ELSE 1 END", m.cid),
        asc: m.attempts,
        asc: fragment("RANDOM()")
      ],
      limit: ^limit
    )
    |> repo().all()
  end

  def bitswap_fetchable_missing_chunks(limit) do
    from(m in MissingChunk,
      where: not is_nil(m.cid) and not is_nil(m.data_hash),
      order_by: [asc: m.attempts, asc: fragment("RANDOM()")],
      limit: ^limit
    )
    |> repo().all()
  end

  def get_missing_chunk(file_id, chunk_index) do
    repo().get_by(MissingChunk, file_id: file_id, chunk_index: chunk_index)
  end

  def increment_missing_chunk_attempts(file_id, chunk_index, now_unix) do
    from(m in MissingChunk,
      where: m.file_id == ^file_id and m.chunk_index == ^chunk_index
    )
    |> repo().update_all(inc: [attempts: 1], set: [updated_at: now_unix])
  end

  def missing_chunk_count(file_id) do
    from(m in MissingChunk, where: m.file_id == ^file_id, select: count())
    |> repo().one()
  end
end
