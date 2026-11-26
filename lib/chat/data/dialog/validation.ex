defmodule Chat.Data.Dialog.Validation do
  @moduledoc "Signature and integrity validation for dialog operations."

  alias Chat.Data.Dialog.Guards
  alias Chat.Data.Dialog.Versioning
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Schemas.DialogMessageReceipt
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

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
    |> Guards.validate_participant(
      :sender_hash,
      message_struct.dialog_hash,
      message_struct.sender_hash
    )
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
         :ok <- Guards.check_dialog_key_published(dialog_hash, sender_hash) do
      :ok
    else
      {:error, reason} -> {:error, reason}
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
      {:insert, true} -> Versioning.check_insert_versioning(changeset)
      {:update, true} -> Versioning.check_update_versioning(changeset)
      _ -> changeset
    end
  end

  def message_pre_apply_versioning(multi, changeset, context) do
    Versioning.pre_apply_versioning(multi, changeset, context)
  end

  # --- Dialog Message Reactions: Peer sync validation ---

  def validate_reaction_insert(reaction_struct) do
    %DialogMessageReaction{}
    |> DialogMessageReaction.create_changeset(Map.from_struct(reaction_struct))
    |> UserValidation.validate_signature()
    |> Guards.validate_participant(
      :reactor_hash,
      reaction_struct.dialog_hash,
      reaction_struct.reactor_hash
    )
    |> Guards.validate_message_in_dialog(reaction_struct.message_id, reaction_struct.dialog_hash)
    |> Guards.validate_not_self_reaction(reaction_struct.message_id, reaction_struct.reactor_hash)
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
    {reactor_hash, dialog_hash, message_id} =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          {changes["reactor_hash"] || changes[:reactor_hash],
           changes["dialog_hash"] || changes[:dialog_hash],
           changes["message_id"] || changes[:message_id]}

        %Operation{operation: :update, data: data} ->
          {data["reactor_hash"], data["dialog_hash"], data["message_id"]}
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(reactor_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey),
         :ok <- Guards.check_participant(dialog_hash, reactor_hash),
         :ok <- Guards.check_message_in_dialog(message_id, dialog_hash),
         :ok <- Guards.check_not_self_reaction(message_id, reactor_hash) do
      :ok
    else
      {:error, reason} -> {:error, reason}
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
    |> Guards.validate_participant(
      :peer_hash,
      receipt_struct.dialog_hash,
      receipt_struct.peer_hash
    )
    |> Guards.validate_message_in_dialog(receipt_struct.message_id, receipt_struct.dialog_hash)
    |> Guards.validate_not_self_receipt(receipt_struct.message_id, receipt_struct.peer_hash)
  end

  # --- Dialog Message Receipts: HTTP ingestion ---

  def receipt_allowed(
        %Operation{operation: :insert, changes: changes},
        %{challenge: challenge, signature: signature}
      ) do
    peer_hash = changes["peer_hash"] || changes[:peer_hash]
    dialog_hash = changes["dialog_hash"] || changes[:dialog_hash]
    message_id = changes["message_id"] || changes[:message_id]

    with %{sign_pkey: sign_pkey} <- UserData.get_card(peer_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey),
         :ok <- Guards.check_participant(dialog_hash, peer_hash),
         :ok <- Guards.check_message_in_dialog(message_id, dialog_hash),
         :ok <- Guards.check_not_self_receipt(message_id, peer_hash) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Invalid operation"}
    end
  end

  def receipt_validate(receipt, changes, :insert) do
    receipt
    |> DialogMessageReceipt.create_changeset(changes)
    |> UserValidation.validate_signature()
  end
end
