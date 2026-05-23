defmodule Chat.Data.Dialog.Versioning do
  @moduledoc """
  Handles versioning logic for dialog_messages records.

  When a dialog message is edited, the old version is archived to
  dialog_messages_versions and the new version replaces it in dialog_messages.

  Used by both peer sync (ShapeWriter) and HTTP ingestion (ElectricController).
  """

  import Ecto.Query

  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageVersion
  alias Ecto.Multi

  @dialyzer {:no_opaque, archive_and_insert: 3, archive_and_update: 3}

  def handle_insert_with_conflict(repo, existing, new_message) do
    if new_message.owner_timestamp > existing.owner_timestamp do
      archive_and_insert(repo, existing, new_message)
    else
      archive_changeset(new_message)
      |> repo.insert(
        on_conflict: :nothing,
        conflict_target: [:message_id, :sign_hash]
      )
    end
  end

  def handle_update_with_versioning(repo, existing, new_message) do
    if new_message.owner_timestamp > existing.owner_timestamp do
      archive_and_update(repo, existing, new_message)
    else
      archive_changeset(new_message)
      |> repo.insert(
        on_conflict: :nothing,
        conflict_target: [:message_id, :sign_hash]
      )
    end
  end

  defp archive_and_insert(repo, existing, new_message) do
    Multi.new()
    |> archive_multi_insert(:archive, existing)
    |> Multi.insert(
      :update_main,
      DialogMessage.create_changeset(%DialogMessage{}, %{
        message_id: new_message.message_id,
        dialog_hash: new_message.dialog_hash,
        sender_hash: new_message.sender_hash,
        content_b64: new_message.content_b64,
        deleted_flag: new_message.deleted_flag,
        refs_map_b64: new_message.refs_map_b64,
        parent_sign_hash: existing.sign_hash,
        owner_timestamp: new_message.owner_timestamp,
        sign_b64: new_message.sign_b64,
        sign_hash: new_message.sign_hash
      }),
      on_conflict: message_upsert_query(),
      conflict_target: :message_id,
      allow_stale: true
    )
    |> repo.transaction()
    |> case do
      {:ok, %{update_main: result}} -> {:ok, result}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp archive_and_update(repo, existing, new_message) do
    Multi.new()
    |> archive_multi_insert(:archive, existing)
    |> Multi.update(
      :update_main,
      DialogMessage.update_changeset(existing, %{
        content_b64: new_message.content_b64,
        deleted_flag: new_message.deleted_flag,
        refs_map_b64: new_message.refs_map_b64,
        parent_sign_hash: existing.sign_hash,
        owner_timestamp: new_message.owner_timestamp,
        sign_b64: new_message.sign_b64,
        sign_hash: new_message.sign_hash
      })
    )
    |> repo.transaction()
    |> case do
      {:ok, %{update_main: result}} -> {:ok, result}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
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

  def archive_multi_insert(multi, name, message) do
    Multi.insert(multi, name, archive_changeset(message),
      on_conflict: :nothing,
      conflict_target: [:message_id, :sign_hash],
      allow_stale: true
    )
  end

  def archive_changeset(message) do
    DialogMessageVersion.changeset(%DialogMessageVersion{}, %{
      message_id: message.message_id,
      sign_hash: message.sign_hash,
      dialog_hash: message.dialog_hash,
      sender_hash: message.sender_hash,
      content_b64: message.content_b64,
      deleted_flag: message.deleted_flag,
      refs_map_b64: message.refs_map_b64,
      parent_sign_hash: message.parent_sign_hash,
      owner_timestamp: message.owner_timestamp,
      sign_b64: message.sign_b64
    })
  end
end
