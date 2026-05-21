defmodule Chat.Data.Dialog.Validation do
  @moduledoc "Signature and integrity validation for dialog key operations."

  alias Chat.Data.Schemas.DialogKey
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
end
