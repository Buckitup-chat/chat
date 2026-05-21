defmodule Chat.Data.Dialog do
  @moduledoc "Dialog context for managing dialog data in Postgres"

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.DialogKey

  def get_dialog_key(dialog_hash, sender_hash) do
    repo().get_by(DialogKey, dialog_hash: dialog_hash, sender_hash: sender_hash)
  end

  def upsert_dialog_key(changeset) do
    repo().insert(changeset,
      on_conflict: dialog_key_upsert_query(),
      conflict_target: [:dialog_hash, :sender_hash],
      allow_stale: true
    )
  end

  defp dialog_key_upsert_query do
    from(dk in DialogKey,
      update: [
        set: [
          peer_hash: fragment("EXCLUDED.peer_hash"),
          peer_kem_wrap_key_b64: fragment("EXCLUDED.peer_kem_wrap_key_b64"),
          peer_wrapped_msg_key_b64: fragment("EXCLUDED.peer_wrapped_msg_key_b64"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          sign_b64: fragment("EXCLUDED.sign_b64")
        ]
      ],
      where:
        is_nil(dk.owner_timestamp) or
          dk.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end
end
