defmodule Chat.Repo.Migrations.CreateUploadChunks do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE upload_chunks (
      file_id TEXT NOT NULL,
      chunk_index INTEGER NOT NULL,
      chunk_sign_hash BYTEA NOT NULL,
      uploader_hash TEXT NOT NULL,
      size INTEGER NOT NULL,
      updated_at BIGINT NOT NULL,
      PRIMARY KEY (file_id, chunk_index)
    )
    """

    create index(:upload_chunks, [:uploader_hash])
    create index(:upload_chunks, [:updated_at])
  end

  def down do
    drop table(:upload_chunks)
  end
end
