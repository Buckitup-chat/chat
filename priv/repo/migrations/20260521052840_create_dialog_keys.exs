defmodule Chat.Repo.Migrations.CreateDialogKeys do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE dialog_keys (
      dialog_hash TEXT NOT NULL,
      sender_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      peer_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      peer_kem_wrap_key_b64 BYTEA NOT NULL,
      peer_wrapped_msg_key_b64 BYTEA NOT NULL,
      owner_timestamp BIGINT NOT NULL,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      sign_b64 BYTEA NOT NULL,
      PRIMARY KEY (dialog_hash, sender_hash),
      CONSTRAINT dialog_keys_dialog_hash_format CHECK (dialog_hash ~ '^di_[a-f0-9]{128}$'),
      CONSTRAINT dialog_keys_sender_hash_format CHECK (sender_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT dialog_keys_peer_hash_format CHECK (peer_hash ~ '^u_[a-f0-9]{128}$')
    )
    """
  end

  def down do
    drop table(:dialog_keys)
  end
end
