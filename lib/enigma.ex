defmodule Enigma do
  @moduledoc """
  Encription related functions
  """

  defdelegate generate_keys, to: Enigma.Crypt

  defdelegate generate_secret, to: Enigma.Crypt
  defdelegate compute_secret(private_key, public_key), to: Enigma.Crypt

  defdelegate encrypt(bitstring, private_key, public_key), to: Enigma.Crypt
  defdelegate decrypt(encrypted_bitstring, private_key, public_key), to: Enigma.Crypt
  defdelegate encrypt_and_sign(bitstring, private_key, public_key), to: Enigma.Crypt

  defdelegate decrypt_signed(
                encrypted_and_signed_tuple,
                private_key,
                public_key,
                author_public_key
              ),
              to: Enigma.Crypt

  defdelegate cipher(plain_iodata, secret), to: Enigma.Cipher
  defdelegate decipher(ciphered_iodata, secret), to: Enigma.Cipher

  defdelegate hash(hashable), to: Enigma.Hash

  @deprecated "implement? render_data protocol"
  defdelegate short_hash(hashable), to: Enigma.Hash
end
