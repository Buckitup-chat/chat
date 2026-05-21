defmodule Chat.Data.Dialog.Validation do
  @moduledoc "Signature and integrity validation for dialog operations."

  alias Chat.Data.Dialog
  alias Chat.Data.Dialog.Versioning
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  import Chat.Db, only: [repo: 0]

  # --- Peer sync validation ---

  def validate_dialog_key_insert(dialog_key_struct) do
    %DialogKey{}
    |> DialogKey.create_changeset(Map.from_struct(dialog_key_struct))
    |> UserValidation.validate_signature()
  end

  def validate_dialog_key_update(existing, dialog_key_struct) do
    attrs =
      dialog_key_struct
      |> Map.from_struct()
      |> Map.take([
        :peer_kem_wrap_key_b64,
        :peer_wrapped_msg_key_b64,
        :owner_timestamp,
        :deleted_flag,
        :sign_b64
      ])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> DialogKey.update_changeset(attrs)
    |> UserValidation.validate_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  # --- HTTP ingestion ---

  def dialog_key_allowed(operation, %{challenge: challenge, signature: signature}) do
    sender_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["sender_hash"] || changes[:sender_hash]

        %Operation{operation: :update, data: %{"sender_hash" => hash}} ->
          hash
      end

    card = UserData.get_card(sender_hash)
    true = EnigmaPq.verify(challenge, signature, card.sign_pkey)
    :ok
  rescue
    _ -> {:error, "Invalid operation"}
  end

  def dialog_key_validate(dialog_key, changes, op) do
    case op do
      :insert ->
        dialog_key
        |> DialogKey.create_changeset(changes)
        |> UserValidation.validate_signature()

      :update ->
        dialog_key
        |> DialogKey.update_changeset(changes)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end

  # --- Dialog Messages: Peer sync validation ---

  def validate_message_insert(message_struct) do
    %DialogMessage{}
    |> DialogMessage.create_changeset(Map.from_struct(message_struct))
    |> UserValidation.validate_signature()
  end

  def validate_message_update(existing, message_struct) do
    attrs =
      message_struct
      |> Map.from_struct()
      |> Map.take([
        :content_b64,
        :deleted_flag,
        :refs_map_b64,
        :parent_sign_hash,
        :owner_timestamp,
        :sign_b64,
        :sign_hash
      ])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> DialogMessage.update_changeset(attrs)
    |> UserValidation.validate_signature()
  end

  # --- Dialog Messages: HTTP ingestion ---

  def message_allowed(operation, %{challenge: challenge, signature: signature}) do
    sender_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["sender_hash"] || changes[:sender_hash]

        %Operation{operation: :update, data: %{"sender_hash" => hash}} ->
          hash
      end

    card = UserData.get_card(sender_hash)
    true = EnigmaPq.verify(challenge, signature, card.sign_pkey)
    :ok
  rescue
    _ -> {:error, "Invalid operation"}
  end

  def message_validate_with_versioning(message, changes, op) do
    changeset =
      case op do
        :insert ->
          message
          |> DialogMessage.create_changeset(changes)
          |> UserValidation.validate_signature()

        :update ->
          message
          |> DialogMessage.update_changeset(changes)
          |> UserValidation.validate_signature()
      end

    case {op, changeset.valid?} do
      {:insert, true} ->
        with {:ok, new_message} <- Ecto.Changeset.apply_action(changeset, :insert),
             existing when not is_nil(existing) <- Dialog.get_message(new_message.message_id) do
          handle_insert_with_versioning(changeset, existing, new_message)
        else
          _ -> changeset
        end

      {:update, true} ->
        with {:ok, new_message} <- Ecto.Changeset.apply_action(changeset, :update),
             existing <- changeset.data do
          handle_update_with_versioning(changeset, existing, new_message)
        else
          _ -> changeset
        end

      _ ->
        changeset
    end
  end

  defp handle_insert_with_versioning(changeset, existing, new_message) do
    if new_message.owner_timestamp > existing.owner_timestamp do
      Ecto.Changeset.put_change(changeset, :parent_sign_hash, existing.sign_hash)
    else
      %{changeset | action: :ignore}
    end
  end

  defp handle_update_with_versioning(changeset, existing, new_message) do
    if new_message.owner_timestamp > existing.owner_timestamp do
      Ecto.Changeset.put_change(changeset, :parent_sign_hash, existing.sign_hash)
    else
      %{changeset | action: :ignore}
    end
  end

  def message_pre_apply_versioning(multi, changeset, _context) do
    cond do
      changeset.valid? and changeset.action != :ignore ->
        archive_message_if_newer(multi, changeset)

      changeset.action == :ignore ->
        archive_old_message_version(multi, changeset)

      true ->
        multi
    end
  end

  defp archive_message_if_newer(multi, changeset) do
    case Ecto.Changeset.apply_action(changeset, changeset.action || :insert) do
      {:ok, new_message} ->
        existing = fetch_existing_message(changeset, new_message)

        if existing && new_message.owner_timestamp > existing.owner_timestamp do
          Versioning.archive_multi_insert(multi, :archive_existing, existing)
        else
          multi
        end

      _ ->
        multi
    end
  end

  defp fetch_existing_message(%{action: :update, data: data}, _new_message), do: data

  defp fetch_existing_message(_changeset, new_message) do
    repo().get(DialogMessage, new_message.message_id)
  end

  defp archive_old_message_version(multi, changeset) do
    case Ecto.Changeset.apply_action(%{changeset | action: :insert}, :insert) do
      {:ok, new_message} ->
        Versioning.archive_multi_insert(multi, :archive_old_version, new_message)

      _ ->
        multi
    end
  end
end
