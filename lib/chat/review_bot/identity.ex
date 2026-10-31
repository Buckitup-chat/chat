defmodule Chat.ReviewBot.Identity do
  @moduledoc "Pure functions for encoding, encrypting, and verifying bot identities."

  alias EnigmaPq

  @origin_salt "buckitup/origin-bot/v1"
  @auth_token_salt "buckitup/origin-bot-auth/v1"
  @version 1

  def origin_salt, do: @origin_salt
  def auth_token_salt, do: @auth_token_salt

  def encode(%{sign_skey: sign_skey, crypt_skey: crypt_skey}) do
    %{
      "v" => @version,
      "sign_skey" => Base.encode64(sign_skey),
      "crypt_skey" => Base.encode64(crypt_skey)
    }
    |> Jason.encode!()
  end

  def decode(binary) when is_binary(binary) do
    with {:ok, %{"v" => 1, "sign_skey" => s, "crypt_skey" => c}} <- Jason.decode(binary),
         {:ok, sign_skey} <- Base.decode64(s),
         {:ok, crypt_skey} <- Base.decode64(c) do
      {:ok, %{sign_skey: sign_skey, crypt_skey: crypt_skey}}
    else
      {:ok, _} -> {:error, :unsupported_version}
      {:error, _} -> {:error, :invalid_json}
      :error -> {:error, :decode_failed}
    end
  end

  def wrap(identity, crypt_pkey) do
    identity
    |> encode()
    |> EnigmaPq.kem_encrypt(crypt_pkey, @origin_salt)
  end

  def unwrap(secret, encrypted, crypt_skey) do
    case EnigmaPq.kem_decrypt(secret, encrypted, crypt_skey, @origin_salt) do
      plaintext when is_binary(plaintext) -> decode(plaintext)
      _ -> {:error, :decryption_failed}
    end
  end

  def wrap_token(nil, _crypt_pkey), do: {nil, nil}

  def wrap_token(auth_token, crypt_pkey) when is_binary(auth_token) do
    EnigmaPq.kem_encrypt(auth_token, crypt_pkey, @auth_token_salt)
  end

  def unwrap_token(nil, _encrypted, _crypt_skey), do: {:ok, nil}
  def unwrap_token(_secret, nil, _crypt_skey), do: {:ok, nil}

  def unwrap_token(secret, encrypted, crypt_skey) do
    case EnigmaPq.kem_decrypt(secret, encrypted, crypt_skey, @auth_token_salt) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      _ -> {:error, :decryption_failed}
    end
  end

  def matches_card?(identity, user_card) do
    probe = :crypto.strong_rand_bytes(32)
    signature = EnigmaPq.sign(probe, identity.sign_skey)
    EnigmaPq.verify(probe, signature, user_card.sign_pkey)
  end
end
