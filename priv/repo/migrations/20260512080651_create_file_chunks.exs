defmodule Chat.Repo.Migrations.CreateFileChunks do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE file_chunks (
      file_id TEXT NOT NULL,
      chunk_index INTEGER NOT NULL,
      data_b64 BYTEA NOT NULL,
      size INTEGER NOT NULL,
      uploader_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      PRIMARY KEY (file_id, chunk_index)
    )
    """

    execute "ALTER TABLE file_chunks ALTER COLUMN data_b64 SET STORAGE EXTERNAL"

    execute """
    ALTER TABLE file_chunks SET (
      autovacuum_vacuum_scale_factor = 0.01,
      autovacuum_analyze_scale_factor = 0.02,
      autovacuum_vacuum_cost_delay = 40
    )
    """
  end

  def down do
    drop table(:file_chunks)
  end
end
