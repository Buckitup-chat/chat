defmodule Chat.Repo.Migrations.CreateOrigins do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE origins (
      origin_hash TEXT PRIMARY KEY REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      owner_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      owner_cert BYTEA NOT NULL,
      name TEXT NOT NULL,
      moderation_mode TEXT NOT NULL DEFAULT 'none',
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      sign_hash TEXT NOT NULL,
      CONSTRAINT origins_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT origins_owner_hash_format CHECK (owner_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT origins_sign_hash_format CHECK (sign_hash ~ '^ors_[a-f0-9]{128}$'),
      CONSTRAINT origins_moderation_mode_values CHECK (moderation_mode IN ('none', 'post', 'pre'))
    )
    """

    execute "ALTER TABLE origins ALTER COLUMN owner_cert SET STORAGE EXTERNAL"
    execute "ALTER TABLE origins ALTER COLUMN sign_b64 SET STORAGE EXTERNAL"

    execute "CREATE INDEX origins_owner_hash ON origins(owner_hash)"
  end

  def down do
    drop table(:origins)
  end
end
