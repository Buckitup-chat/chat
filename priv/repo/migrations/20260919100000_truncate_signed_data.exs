defmodule Chat.Repo.Migrations.TruncateSignedData do
  use Ecto.Migration

  @moduledoc """
  Wipe all rows that carry signatures computed with the old
  (non-length-framed) canonical serialization.

  The signing algorithm changed to length-framed fields
  (u32be(byte_length) || encoded_value), making every existing
  sign_b64 / sign_hash invalid.  Re-signing is impossible without
  the owners' private keys, so the data must be re-created by clients.

  TRUNCATE … CASCADE handles FK ordering automatically.
  """

  @signed_tables ~w[
    user_cards
    user_storage
    user_storage_versions
    dialog_messages
    dialog_messages_versions
    dialog_keys
    dialog_message_reactions
    dialog_message_receipts
    files
    file_chunks
    origins
    review
    review_versions
    review_list
    review_post_right
    review_revoke_right
    review_post_right_candidate
    review_revoke_right_candidate
    review_public_passwords
    review_password_candidate
  ]

  @bookkeeping_tables ~w[
    upload_chunks
    missing_chunks
  ]

  def up do
    tables = (@signed_tables ++ @bookkeeping_tables) |> Enum.join(", ")
    execute "TRUNCATE #{tables} CASCADE"
  end

  def down do
    # Data cannot be restored — this migration is intentionally irreversible.
    :ok
  end
end
