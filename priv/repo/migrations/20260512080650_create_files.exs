defmodule Chat.Repo.Migrations.CreateFiles do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE files (
      file_id TEXT PRIMARY KEY,
      uploader_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      total_size BIGINT NOT NULL,
      chunk_size INTEGER NOT NULL DEFAULT 4194304,
      chunk_count INTEGER NOT NULL,
      chunk_sign_hashes BYTEA[] NOT NULL,
      owner_timestamp BIGINT NOT NULL,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      sign_b64 BYTEA NOT NULL,
      CONSTRAINT file_id_format_check CHECK (file_id ~ '^f_[a-f0-9]{32}$')
    )
    """
  end

  def down do
    drop table(:files)
  end
end
