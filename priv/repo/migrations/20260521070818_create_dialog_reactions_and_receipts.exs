defmodule Chat.Repo.Migrations.CreateDialogReactionsAndReceipts do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE dialog_message_reactions (
      reaction_hash TEXT PRIMARY KEY,
      dialog_hash TEXT NOT NULL,
      message_id TEXT NOT NULL,
      message_sign_hash TEXT NOT NULL,
      reactor_hash TEXT NOT NULL,
      type_b64 BYTEA NOT NULL,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      CONSTRAINT dmreact_reaction_hash_format CHECK (reaction_hash ~ '^dmr_[a-f0-9]{128}$'),
      CONSTRAINT dmreact_dialog_hash_format CHECK (dialog_hash ~ '^di_[a-f0-9]{128}$'),
      CONSTRAINT dmreact_message_id_format CHECK (message_id ~ '^dmsg_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
      CONSTRAINT dmreact_message_sign_hash_format CHECK (message_sign_hash ~ '^dms_[a-f0-9]{128}$'),
      CONSTRAINT dmreact_reactor_hash_format CHECK (reactor_hash ~ '^u_[a-f0-9]{128}$')
    )
    """

    execute """
    CREATE TABLE dialog_message_receipts (
      receipt_hash TEXT PRIMARY KEY,
      dialog_hash TEXT NOT NULL,
      message_id TEXT NOT NULL,
      peer_hash TEXT NOT NULL,
      type TEXT NOT NULL,
      message_sign_hash TEXT NOT NULL,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      CONSTRAINT dmreceipt_receipt_hash_format CHECK (receipt_hash ~ '^dmrc_[a-f0-9]{128}$'),
      CONSTRAINT dmreceipt_dialog_hash_format CHECK (dialog_hash ~ '^di_[a-f0-9]{128}$'),
      CONSTRAINT dmreceipt_message_id_format CHECK (message_id ~ '^dmsg_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
      CONSTRAINT dmreceipt_peer_hash_format CHECK (peer_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT dmreceipt_message_sign_hash_format CHECK (message_sign_hash ~ '^dms_[a-f0-9]{128}$'),
      CONSTRAINT dmreceipt_type_values CHECK (type IN ('delivered', 'read'))
    )
    """
  end

  def down do
    drop table(:dialog_message_receipts)
    drop table(:dialog_message_reactions)
  end
end
