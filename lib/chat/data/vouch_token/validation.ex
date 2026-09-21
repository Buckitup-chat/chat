defmodule Chat.Data.VouchToken.Validation do
  @moduledoc "Validation for vouch_token operations."

  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  # --- Peer sync validation ---

  def validate_vouch_token_insert(vt_struct) do
    %VouchToken{}
    |> VouchToken.create_changeset(Map.from_struct(vt_struct))
    |> UserValidation.validate_signature()
  end

  def validate_vouch_token_update(existing, vt_struct) do
    attrs =
      vt_struct
      |> Map.from_struct()
      |> Map.take([:deleted_flag, :owner_timestamp, :sign_b64])

    existing
    |> VouchToken.update_changeset(attrs)
    |> UserValidation.validate_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  # --- HTTP ingestion ---

  def vouch_token_allowed(operation, %{challenge: challenge, signature: signature}) do
    issuer_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["issuer_hash"] || changes[:issuer_hash]

        %Operation{operation: :update, data: %{"issuer_hash" => hash}} ->
          hash
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(issuer_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def vouch_token_validate(vt, changes, op) do
    case op do
      :insert ->
        vt
        |> VouchToken.create_changeset(changes)
        |> UserValidation.validate_signature()

      :update ->
        vt
        |> VouchToken.update_changeset(changes)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end
end
