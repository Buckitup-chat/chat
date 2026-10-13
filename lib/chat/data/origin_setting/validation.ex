defmodule Chat.Data.OriginSetting.Validation do
  @moduledoc "Signature and integrity validation for origin setting operations."

  alias Chat.Data.Integrity
  alias Chat.Data.Origin, as: OriginData
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Schemas.OriginSetting
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  def validate_origin_setting_insert(setting_struct) do
    %OriginSetting{}
    |> OriginSetting.create_changeset(Map.from_struct(setting_struct))
    |> UserValidation.validate_signature()
  end

  def validate_origin_setting_update(existing, setting_struct) do
    attrs =
      setting_struct
      |> Map.from_struct()
      |> Map.take([:value, :deleted_flag, :owner_timestamp, :sign_b64])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> OriginSetting.update_changeset(attrs)
    |> validate_update_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  def origin_setting_allowed(%Operation{} = operation, pop_context) do
    origin_or_owner_auth(operation, pop_context)
  end

  def origin_setting_validate(setting, changes, op) do
    case op do
      :insert ->
        setting
        |> OriginSetting.create_changeset(changes)
        |> UserValidation.validate_signature()

      :update ->
        setting
        |> OriginSetting.update_changeset(changes)
        |> validate_update_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end

  defp validate_update_signature(changeset) do
    with {:ok, data} <- Ecto.Changeset.apply_action(changeset, :validate),
         {:error, _} <- Integrity.verify_signature(data),
         {:error, _} <- verify_owner_signature(data) do
      Ecto.Changeset.add_error(changeset, :sign_b64, "invalid signature")
    else
      _ -> changeset
    end
  end

  defp verify_owner_signature(data) do
    payload = Integrity.signature_payload(data)

    with %Origin{owner_hash: owner_hash} <- OriginData.get_origin(data.origin_hash),
         %{sign_pkey: owner_pkey} <- UserData.get_card(owner_hash),
         true <- EnigmaPq.verify(payload, data.sign_b64, owner_pkey) do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp origin_or_owner_auth(operation, %{challenge: challenge, signature: signature}) do
    origin_hash = extract_origin_hash(operation)

    with %Origin{owner_hash: owner_hash} <- OriginData.get_origin(origin_hash),
         %{sign_pkey: origin_sign_pkey} <- UserData.get_card(origin_hash),
         %{sign_pkey: owner_sign_pkey} <- UserData.get_card(owner_hash),
         false <- EnigmaPq.verify(challenge, signature, origin_sign_pkey),
         false <- EnigmaPq.verify(challenge, signature, owner_sign_pkey) do
      {:error, "Invalid operation"}
    else
      true -> :ok
      _ -> {:error, "Invalid operation"}
    end
  end

  defp extract_origin_hash(%Operation{operation: :insert, changes: changes}) do
    changes["origin_hash"] || changes[:origin_hash]
  end

  defp extract_origin_hash(%Operation{operation: :update, data: %{"origin_hash" => hash}}) do
    hash
  end
end
