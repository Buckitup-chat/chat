defmodule Chat.Data.Dialog do
  @moduledoc "Dialog context for managing dialog data in Postgres"

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Dialog.Versioning
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage

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

  # --- Dialog Messages ---

  def get_message(message_id) do
    repo().get(DialogMessage, message_id)
  end

  def insert_message(changeset) do
    repo().insert(changeset,
      on_conflict: message_upsert_query(),
      conflict_target: :message_id,
      allow_stale: true
    )
  end

  def insert_message_with_conflict(existing, new_message) do
    Versioning.handle_insert_with_conflict(repo(), existing, new_message)
  end

  def update_message_with_versioning(existing, new_message) do
    Versioning.handle_update_with_versioning(repo(), existing, new_message)
  end

  defp message_upsert_query do
    from(m in DialogMessage,
      update: [
        set: [
          content_b64: fragment("EXCLUDED.content_b64"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          refs_map_b64: fragment("EXCLUDED.refs_map_b64"),
          parent_sign_hash: fragment("EXCLUDED.parent_sign_hash"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64"),
          sign_hash: fragment("EXCLUDED.sign_hash")
        ]
      ],
      where:
        is_nil(m.owner_timestamp) or
          m.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
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
