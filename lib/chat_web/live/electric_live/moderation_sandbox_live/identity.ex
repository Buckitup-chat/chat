defmodule ChatWeb.ElectricLive.ModerationSandboxLive.Identity do
  @moduledoc """
  Origin identity import for the moderation sandbox.

  Accepts the JSON exported by the Origin Owner Sandbox and proves the imported
  secret keys belong to the origin's `user_cards` row: a signature round-trip
  against `sign_pkey` and a KEM round-trip against `crypt_pkey`. The server
  re-checks the signing key on every ingest — this is the local, pre-flight
  version of the same check, so a wrong export fails visibly on import instead
  of silently on the first moderation action.
  """

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias EnigmaPq

  @required_fields ~w(origin_hash name sign_skey crypt_skey)

  def parse(json_string) do
    with {:ok, data} <- decode_json(json_string),
         :ok <- validate_format(data),
         {:ok, sign_skey} <- decode_key(data, "sign_skey"),
         {:ok, crypt_skey} <- decode_key(data, "crypt_skey") do
      {:ok,
       %{
         origin_hash: data["origin_hash"],
         name: data["name"],
         sign_skey: sign_skey,
         crypt_skey: crypt_skey
       }}
    end
  end

  @doc """
  Proves possession of the origin identity against its published `user_cards`
  row. Returns `:ok` or `{:error, reason}`.
  """
  def verify_against_card(_identity, nil), do: {:error, "no user_cards row for this origin_hash"}

  def verify_against_card(identity, card) do
    sign_pkey = Crypto.decode_binary_field(card.sign_pkey)
    crypt_pkey = Crypto.decode_binary_field(card.crypt_pkey)

    cond do
      not signs_for?(identity.sign_skey, sign_pkey) ->
        {:error, "sign_skey does not match the origin card's sign_pkey"}

      not decrypts_for?(identity.crypt_skey, crypt_pkey) ->
        {:error, "crypt_skey does not match the origin card's crypt_pkey"}

      true ->
        :ok
    end
  end

  # --- Private ---

  defp decode_json(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, "not valid JSON"}
    end
  end

  defp validate_format(%{"type" => "buckitup_origin_identity"} = data) do
    case Enum.find(@required_fields, &(not Map.has_key?(data, &1))) do
      nil -> :ok
      missing -> {:error, "missing field: #{missing}"}
    end
  end

  defp validate_format(_),
    do: {:error, "not an origin identity export (expected type buckitup_origin_identity)"}

  defp decode_key(data, field) do
    case Base.decode64(data[field] || "", padding: false) do
      {:ok, <<_::binary-1, _::binary>> = key} -> {:ok, key}
      _ -> {:error, "invalid or empty #{field}"}
    end
  end

  defp signs_for?(sign_skey, sign_pkey) do
    nonce = :crypto.strong_rand_bytes(32)

    nonce
    |> EnigmaPq.sign(sign_skey)
    |> then(&EnigmaPq.verify(nonce, &1, sign_pkey))
  rescue
    _ -> false
  end

  defp decrypts_for?(crypt_skey, crypt_pkey) do
    {secret, kem_ciphertext} = EnigmaPq.encapsulate_secret(crypt_pkey)
    EnigmaPq.decapsulate_secret(kem_ciphertext, crypt_skey) == secret
  rescue
    _ -> false
  end
end
