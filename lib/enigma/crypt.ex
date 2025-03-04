defmodule Enigma.Crypt do
  @moduledoc """
  Crtypting functions
  """

  alias Enigma.Cipher

  def generate_keys do
    key = Curvy.generate_key()
    private = Curvy.Key.to_privkey(key)
    public = Curvy.Key.to_pubkey(key)

    {private, public}
  end

  def compute_secret(private, public) do
    Curvy.get_shared_secret(private, public)
  end

  def private_to_public(private) do
    Curvy.Key.to_pubkey(Curvy.Key.from_privkey(private))
  end

  def generate_secret do
    :crypto.strong_rand_bytes(32)
  end

  def encrypt(data, private, public) do
    secret = compute_secret(private, public)

    data
    |> Cipher.cipher(secret)
  end

  def encrypt_and_sign(data, private, public) do
    {
      encrypt(data, private, public),
      sign(data, private)
    }
  end

  def encrypt_and_bisign(data, src_private, dst_private) do
    dst_public = Curvy.Key.to_pubkey(Curvy.Key.from_privkey(dst_private))
    {encrypted_data, data_sign} = encrypt_and_sign(data, src_private, dst_public)
    encrypted_data_sign = sign(encrypted_data, dst_private)

    {encrypted_data, data_sign, encrypted_data_sign}
  end

  def decrypt(encrypted_data, private, public) do
    secret = compute_secret(private, public)

    encrypted_data
    |> Cipher.decipher(secret)
  end

  def decrypt_signed({encrypted_data, sign}, private, public, author_public) do
    decrypted = encrypted_data |> decrypt(private, public)

    if valid_sign?(sign, decrypted, author_public),
      do: {:ok, decrypted},
      else: :error
  end

  def decrypt_bisigned({encrypted_data, data_sign, encrypted_data_sign}, private, author_public) do
    public = Curvy.Key.to_pubkey(Curvy.Key.from_privkey(private))

    if valid_sign?(encrypted_data_sign, encrypted_data, public),
      do: decrypt_signed({encrypted_data, data_sign}, private, author_public, author_public),
      else: :error_out_sign
  end

  def sign(data, private) do
    <<_::8, sign::binary>> = Curvy.sign(data, private, compact: true)
    sign
  end

  def valid_sign?(sign, data, public) do
    case sign do
      <<sign::binary-size(64)>> -> <<31, sign::binary>>
      _ -> sign
    end
    |> Curvy.verify(data, public)
    |> then(fn x -> x == true end)
  end
end
