defmodule Chat.Repo.Migrations.CreateDialogMessages do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE dialog_messages (
      message_id TEXT PRIMARY KEY,
      dialog_hash TEXT NOT NULL,
      sender_hash TEXT NOT NULL,
      content_b64 BYTEA,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      refs_map_b64 BYTEA,
      parent_sign_hash TEXT,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      sign_hash TEXT NOT NULL,
      CONSTRAINT dm_message_id_format CHECK (message_id ~ '^dmsg_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
      CONSTRAINT dm_dialog_hash_format CHECK (dialog_hash ~ '^di_[a-f0-9]{128}$'),
      CONSTRAINT dm_sender_hash_format CHECK (sender_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT dm_sign_hash_format CHECK (sign_hash ~ '^dms_[a-f0-9]{128}$'),
      CONSTRAINT dm_parent_sign_hash_format CHECK (parent_sign_hash IS NULL OR parent_sign_hash ~ '^dms_[a-f0-9]{128}$')
    )
    """

    execute """
    CREATE UNIQUE INDEX dialog_messages_dialog_hash_message_id
      ON dialog_messages(dialog_hash, message_id)
    """

    execute "ALTER TABLE dialog_messages ALTER COLUMN content_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE dialog_messages ALTER COLUMN refs_map_b64 SET STORAGE EXTERNAL"

    execute """
    CREATE TABLE dialog_messages_versions (
      message_id TEXT NOT NULL,
      sign_hash TEXT NOT NULL,
      dialog_hash TEXT NOT NULL,
      sender_hash TEXT NOT NULL,
      content_b64 BYTEA,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      refs_map_b64 BYTEA,
      parent_sign_hash TEXT,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      PRIMARY KEY (message_id, sign_hash),
      CONSTRAINT dmv_message_id_format CHECK (message_id ~ '^dmsg_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
      CONSTRAINT dmv_dialog_hash_format CHECK (dialog_hash ~ '^di_[a-f0-9]{128}$'),
      CONSTRAINT dmv_sender_hash_format CHECK (sender_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT dmv_sign_hash_format CHECK (sign_hash ~ '^dms_[a-f0-9]{128}$'),
      CONSTRAINT dmv_parent_sign_hash_format CHECK (parent_sign_hash IS NULL OR parent_sign_hash ~ '^dms_[a-f0-9]{128}$')
    )
    """

    execute "ALTER TABLE dialog_messages_versions ALTER COLUMN content_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE dialog_messages_versions ALTER COLUMN refs_map_b64 SET STORAGE EXTERNAL"

    execute """
    CREATE INDEX dialog_messages_versions_parent_sign_hash
      ON dialog_messages_versions(parent_sign_hash)
    """
  end

  def down do
    drop table(:dialog_messages_versions)
    drop table(:dialog_messages)
  end
end
