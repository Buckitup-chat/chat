defmodule Chat.Content.Storage do
  @moduledoc """
  Simple wrapper over message content storage
  """
  alias Chat.Db

  def get(db_key) do
    Db.get(db_key)
  end

  def get_ciphered(db_key, secret) do
    blob = Db.get(db_key)

    if blob do
      Enigma.decipher(blob, secret)
    end
  end

  def delete(db_key) do
    Db.delete(db_key)
  end

  def cipher_and_store(db_key, data, secret) do
    blob = Enigma.cipher(data, secret)
    Db.put(db_key, blob)

    secret
  end

  def cipher_and_store(db_key, data) do
    secret = Enigma.generate_secret()
    cipher_and_store(db_key, data, secret)
  end

  def cipher_and_pack(db_key, data) do
    secret = Enigma.generate_secret()
    cipher_and_pack(db_key, data, secret)
  end

  def cipher_and_pack(db_key, data, secret) do
    blob = Enigma.cipher(data, secret)
    {secret, {db_key, blob}}
  end
end
