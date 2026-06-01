defmodule ChatWeb.ElectricLive.UserSandboxLive.Identity do
  @moduledoc "Identity serialization and validation for the User Sandbox."

  alias Chat.Data.Types.UserHash

  @identity_keys ~w(user_hash name sign_pkey sign_skey crypt_pkey crypt_skey
                     crypt_cert contact_pkey contact_skey contact_cert)

  def to_json(user) do
    Jason.encode!(
      %{
        type: "buckitup_pq_identity",
        version: 2,
        user_hash: user.user_hash,
        name: user.name,
        sign_pkey: Base.encode64(user.sign_pkey, padding: false),
        sign_skey: Base.encode64(user.sign_skey, padding: false),
        crypt_pkey: Base.encode64(user.crypt_pkey, padding: false),
        crypt_skey: Base.encode64(user.crypt_skey, padding: false),
        crypt_cert: Base.encode64(user.crypt_cert, padding: false),
        contact_pkey: Base.encode64(user.contact_pkey, padding: false),
        contact_skey: Base.encode64(user.contact_skey, padding: false),
        contact_cert: Base.encode64(user.contact_cert, padding: false),
        owner_timestamp: user.owner_timestamp
      },
      pretty: true
    )
  end

  def parse_and_validate(json_string) do
    with {:ok, data} <- Jason.decode(json_string),
         :ok <- validate_identity_format(data),
         {:ok, keys} <- decode_identity_keys(data),
         :ok <- verify_identity_integrity(data["user_hash"], keys) do
      {:ok, build_user_data(data, keys)}
    end
  end

  defp validate_identity_format(%{"type" => "buckitup_pq_identity", "version" => 2} = data) do
    case Enum.find(@identity_keys, &(not Map.has_key?(data, &1))) do
      nil -> :ok
      missing -> {:error, "missing field: #{missing}"}
    end
  end

  defp validate_identity_format(%{"version" => v}) when v < 2,
    do: {:error, "v#{v} format is missing secret keys. Please re-export."}

  defp validate_identity_format(_), do: {:error, "invalid file format"}

  defp decode_identity_keys(data) do
    binary_fields =
      ~w(sign_pkey sign_skey crypt_pkey crypt_skey crypt_cert contact_pkey contact_skey contact_cert)

    Enum.reduce_while(binary_fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case Base.decode64(data[field], padding: false) do
        {:ok, binary} -> {:cont, {:ok, Map.put(acc, String.to_existing_atom(field), binary)}}
        :error -> {:halt, {:error, "invalid base64 in #{field}"}}
      end
    end)
  end

  defp verify_identity_integrity(user_hash, keys) do
    expected_hash = keys.sign_pkey |> EnigmaPq.hash() |> UserHash.from_binary()

    cond do
      user_hash != expected_hash ->
        {:error, "user_hash does not match sign_pkey"}

      not EnigmaPq.verify(keys.crypt_pkey, keys.crypt_cert, keys.sign_pkey) ->
        {:error, "invalid crypt_cert"}

      not EnigmaPq.verify(keys.contact_pkey, keys.contact_cert, keys.sign_pkey) ->
        {:error, "invalid contact_cert"}

      true ->
        :ok
    end
  end

  defp build_user_data(data, keys) do
    keys
    |> Map.put(:user_hash, data["user_hash"])
    |> Map.put(:user_hash_hex, String.slice(data["user_hash"], 2..-1//1))
    |> Map.put(:name, data["name"])
    |> Map.put(:owner_timestamp, data["owner_timestamp"] || 0)
    |> Map.put(:deleted_flag, false)
    |> Map.put(:sign_b64, nil)
  end
end
