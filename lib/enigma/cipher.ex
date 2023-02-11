defmodule Enigma.Cipher do
  @moduledoc """
  Ciphering (symmetric encryption)
  """
  @cipher :blowfish_cfb64

  def cipher(plain_iodata, <<iv::binary-size(8), key::binary-size(16), iv2::binary-size(8)>>) do
    :crypto.crypto_one_time(@cipher, key, :crypto.exor(iv, iv2), plain_iodata, true)
  end

  def decipher(ciphered_iodata, <<iv::binary-size(8), key::binary-size(16), iv2::binary-size(8)>>) do
    :crypto.crypto_one_time(@cipher, key, :crypto.exor(iv, iv2), ciphered_iodata, false)
  end
end
