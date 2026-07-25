defmodule Chat.Repo.Migrations.CreateMissingChunks do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE missing_chunks (
      file_id TEXT NOT NULL,
      chunk_index INTEGER NOT NULL,
      data_hash TEXT,
      size INTEGER,
      peer_url TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      updated_at BIGINT NOT NULL,
      PRIMARY KEY (file_id, chunk_index)
    )
    """

    execute """
    CREATE INDEX missing_chunks_fetchable_idx
      ON missing_chunks (attempts, updated_at)
      WHERE data_hash IS NOT NULL
    """
  end

  def down do
    drop table(:missing_chunks)
  end
end
