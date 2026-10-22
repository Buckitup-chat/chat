defmodule Chat.Data.ReviewWriteToken.Validation do
  @moduledoc "Validation for review_write_token operations."

  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  # --- Peer sync validation ---

  def validate_review_write_token_insert(token_struct) do
    %ReviewWriteToken{}
    |> ReviewWriteToken.create_changeset(Map.from_struct(token_struct))
    |> UserValidation.validate_signature()
  end

  def validate_review_write_token_update(existing, token_struct) do
    attrs =
      token_struct
      |> Map.from_struct()
      |> Map.take([
        :user_hash,
        :review_hash,
        :deleted_flag,
        :owner_timestamp,
        :sign_b64,
        :sign_hash
      ])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> ReviewWriteToken.update_changeset(attrs)
    |> UserValidation.validate_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  # --- HTTP ingestion ---

  def review_write_token_allowed(operation, %{challenge: challenge, signature: signature}) do
    with %{sign_pkey: sign_pkey} <- UserData.get_card(review_bot_hash(operation)),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def review_write_token_validate(token, changes, op) do
    case op do
      :insert ->
        token
        |> ReviewWriteToken.create_changeset(changes)
        |> UserValidation.validate_signature()

      :update ->
        token
        |> ReviewWriteToken.update_changeset(changes)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end

  defp review_bot_hash(%Operation{operation: :insert, changes: changes}),
    do: changes["review_bot_hash"] || changes[:review_bot_hash]

  defp review_bot_hash(%Operation{data: %{"review_bot_hash" => hash}}), do: hash
end
