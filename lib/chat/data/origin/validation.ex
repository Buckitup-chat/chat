defmodule Chat.Data.Origin.Validation do
  @moduledoc "Signature and integrity validation for origin operations."

  alias Chat.Data.Schemas.Origin
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  # --- Peer sync validation ---

  def validate_origin_insert(origin_struct) do
    %Origin{}
    |> Origin.create_changeset(Map.from_struct(origin_struct))
    |> UserValidation.validate_signature()
    |> validate_owner_cert(origin_struct)
  end

  def validate_origin_update(existing, origin_struct) do
    attrs =
      origin_struct
      |> Map.from_struct()
      |> Map.take([
        :name,
        :moderation_mode,
        :deleted_flag,
        :owner_timestamp,
        :sign_b64,
        :sign_hash
      ])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> Origin.update_changeset(attrs)
    |> UserValidation.validate_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  # --- HTTP ingestion ---

  def origin_allowed(operation, %{challenge: challenge, signature: signature}) do
    origin_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["origin_hash"] || changes[:origin_hash]

        %Operation{operation: :update, data: %{"origin_hash" => hash}} ->
          hash
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(origin_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def origin_validate(origin, changes, op) do
    case op do
      :insert ->
        origin
        |> Origin.create_changeset(changes)
        |> UserValidation.validate_signature()
        |> validate_owner_cert_from_changes(changes)

      :update ->
        origin
        |> Origin.update_changeset(changes)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end

  # --- Owner cert validation ---

  defp validate_owner_cert(changeset, origin_struct) do
    verify_owner_cert(
      changeset,
      origin_struct.origin_hash,
      origin_struct.owner_hash,
      origin_struct.owner_cert
    )
  end

  defp validate_owner_cert_from_changes(changeset, changes) do
    verify_owner_cert(
      changeset,
      changes["origin_hash"] || changes[:origin_hash],
      changes["owner_hash"] || changes[:owner_hash],
      changes["owner_cert"] || changes[:owner_cert]
    )
  end

  defp verify_owner_cert(changeset, origin_hash, owner_hash, owner_cert)
       when is_binary(origin_hash) and is_binary(owner_hash) and is_binary(owner_cert) do
    # Skip only when the changeset is already invalid — do NOT let a `false`
    # returned by EnigmaPq.verify/3 collapse into that same branch, or a forged
    # owner_cert would be accepted whenever both user_cards exist.
    if changeset.valid?,
      do: check_owner_cert(changeset, origin_hash, owner_hash, owner_cert),
      else: changeset
  end

  defp verify_owner_cert(changeset, _origin_hash, _owner_hash, _owner_cert) do
    Ecto.Changeset.add_error(changeset, :owner_cert, "invalid owner certificate")
  end

  defp check_owner_cert(changeset, origin_hash, owner_hash, owner_cert) do
    with %{sign_pkey: origin_sign_pkey} <- UserData.get_card(origin_hash),
         %{sign_pkey: owner_sign_pkey} <- UserData.get_card(owner_hash),
         true <- EnigmaPq.verify(origin_sign_pkey, owner_cert, owner_sign_pkey) do
      changeset
    else
      _ -> Ecto.Changeset.add_error(changeset, :owner_cert, "invalid owner certificate")
    end
  end
end
