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
      Curvy.sign(data, private, compact: true)
    }
  end

  def decrypt(encrypted_data, private, public) do
    secret = compute_secret(private, public)

    encrypted_data
    |> Cipher.decipher(secret)
  end

  def decrypt_signed({encrypted_data, sign}, private, public, author_public) do
    decrypted = encrypted_data |> decrypt(private, public)

    if Curvy.verify(sign, decrypted, author_public) do
      {:ok, decrypted}
    else
      :error
    end
  end
end
