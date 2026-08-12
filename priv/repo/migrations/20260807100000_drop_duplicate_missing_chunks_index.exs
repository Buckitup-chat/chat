defmodule Chat.Repo.Migrations.DropDuplicateMissingChunksIndex do
  use Ecto.Migration

  # `missing_chunks_attempts_updated_at_index` (created in
  # 20260627120000_add_source_drive_id_to_missing_chunks) duplicates
  # `missing_chunks_fetchable_idx` (created in 20260613120002_create_missing_chunks) —
  # same columns (attempts, updated_at) and same partial predicate. Drop the redundant one.

  def up do
    execute("DROP INDEX IF EXISTS missing_chunks_attempts_updated_at_index")
  end

  def down do
    execute("""
    CREATE INDEX missing_chunks_attempts_updated_at_index
      ON missing_chunks (attempts, updated_at)
      WHERE data_hash IS NOT NULL
    """)
  end
end
