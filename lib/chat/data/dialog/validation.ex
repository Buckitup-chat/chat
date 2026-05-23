defmodule Chat.Data.Dialog.Validation do
  @moduledoc "Signature and integrity validation for dialog operations."

  alias Chat.Data.Dialog
  alias Chat.Data.Dialog.Versioning
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Schemas.DialogMessageReceipt
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

    with %{sign_pkey: sign_pkey} <- UserData.get_card(sender_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
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
    {sender_hash, dialog_hash} =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          {changes["sender_hash"] || changes[:sender_hash],
           changes["dialog_hash"] || changes[:dialog_hash]}

        %Operation{operation: :update, data: data} ->
          {data["sender_hash"], data["dialog_hash"]}
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(sender_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey),
         %DialogKey{} <- Dialog.get_dialog_key(dialog_hash, sender_hash) do
      :ok
    else
      nil -> {:error, "dialog_key required before sending messages"}
      _ -> {:error, "Invalid operation"}
    end
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
             %DialogMessage{} = existing <- Dialog.get_message(new_message.message_id) do
          handle_insert_with_versioning(changeset, existing, new_message)
        else
          _ -> changeset
        end

      {:update, true} ->
        case Ecto.Changeset.apply_action(changeset, :update) do
          {:ok, new_message} ->
            handle_update_with_versioning(changeset, changeset.data, new_message)

          _ ->
            changeset
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

  # --- Dialog Message Reactions: Peer sync validation ---

  def validate_reaction_insert(reaction_struct) do
    %DialogMessageReaction{}
    |> DialogMessageReaction.create_changeset(Map.from_struct(reaction_struct))
    |> UserValidation.validate_signature()
  end

  def validate_reaction_update(existing, reaction_struct) do
    attrs =
      reaction_struct
      |> Map.from_struct()
      |> Map.take([:type_b64, :deleted_flag, :owner_timestamp, :sign_b64])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> DialogMessageReaction.update_changeset(attrs)
    |> UserValidation.validate_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  # --- Dialog Message Reactions: HTTP ingestion ---

  def reaction_allowed(operation, %{challenge: challenge, signature: signature}) do
    reactor_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["reactor_hash"] || changes[:reactor_hash]

        %Operation{operation: :update, data: %{"reactor_hash" => hash}} ->
          hash
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(reactor_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def reaction_validate(reaction, changes, op) do
    case op do
      :insert ->
        reaction
        |> DialogMessageReaction.create_changeset(changes)
        |> UserValidation.validate_signature()

      :update ->
        reaction
        |> DialogMessageReaction.update_changeset(changes)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end

  # --- Dialog Message Receipts: Peer sync validation ---

  def validate_receipt_insert(receipt_struct) do
    %DialogMessageReceipt{}
    |> DialogMessageReceipt.create_changeset(Map.from_struct(receipt_struct))
    |> UserValidation.validate_signature()
  end

  # --- Dialog Message Receipts: HTTP ingestion ---

  def receipt_allowed(
        %Operation{operation: :insert, changes: changes},
        %{challenge: challenge, signature: signature}
      ) do
    peer_hash = changes["peer_hash"] || changes[:peer_hash]

    with %{sign_pkey: sign_pkey} <- UserData.get_card(peer_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def receipt_validate(receipt, changes, :insert) do
    receipt
    |> DialogMessageReceipt.create_changeset(changes)
    |> UserValidation.validate_signature()
  end
end
