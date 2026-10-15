defmodule Chat.Data.OriginBot.Validation do
  @moduledoc "Signature and integrity validation for origin bot operations."

  alias Chat.Data.Schemas.OriginBot
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  def validate_origin_bot_insert(bot_struct) do
    %OriginBot{}
    |> OriginBot.create_changeset(Map.from_struct(bot_struct))
    |> UserValidation.validate_signature()
  end

  def validate_origin_bot_update(existing, bot_struct) do
    attrs =
      bot_struct
      |> Map.from_struct()
      |> Map.take([:deleted_flag, :owner_timestamp, :sign_b64, :sign_hash])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> OriginBot.update_changeset(attrs)
    |> validate_update_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  def origin_bot_allowed(operation, %{challenge: challenge, signature: signature}) do
    with %{sign_pkey: sign_pkey} <- UserData.get_card(origin_hash(operation)),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def origin_bot_validate(bot, changes, op) do
    case op do
      :insert ->
        bot
        |> OriginBot.create_changeset(changes)
        |> UserValidation.validate_signature()

      :update ->
        bot
        |> OriginBot.update_changeset(changes)
        |> validate_update_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end

  defp validate_update_signature(changeset) do
    UserValidation.validate_signature(changeset)
  end

  defp origin_hash(%Operation{operation: :insert, changes: changes}),
    do: changes["origin_hash"] || changes[:origin_hash]

  defp origin_hash(%Operation{data: %{"origin_hash" => hash}}), do: hash
end
