defmodule EnigmaPq do
  @moduledoc """
  Encryption primitives using OTP 28 functions for Post-Quantum Cryptography.
  Uses ML-DSA-87 for signing and ML-KEM-1024 for key encapsulation.
  """

  @doc """
  Computes SHA3-512 hash of the data.
  """
  def hash(data) do
    :crypto.hash(:sha3_512, data)
  end

  @doc """
  Generates a new user identity with signing (ML-DSA-87) and encryption (ML-KEM-1024) keypairs.
  Returns a map with keys: :sign_pkey, :sign_skey, :crypt_pkey, :crypt_skey.
  """
  def generate_identity do
    {sign_pkey, sign_skey} = generate_sign_keypair()
    {crypt_pkey, crypt_skey} = generate_crypt_keypair()

    %{
      sign_skey: sign_skey,
      sign_pkey: sign_pkey,
      crypt_skey: crypt_skey,
      crypt_pkey: crypt_pkey
    }
  end

  @doc """
  Generates a ML-DSA-87 signing keypair.
  Returns {public_key, private_key}.
  """
  def generate_sign_keypair do
    :crypto.generate_key(:mldsa87, [])
  end

  @doc """
  Generates a ML-KEM-1024 encryption keypair.
  Returns {public_key, private_key}.
  """
  def generate_crypt_keypair do
    :crypto.generate_key(:mlkem1024, [])
  end

  @doc """
  Signs data using the signing secret key (ML-DSA-87).
  """
  def sign(data, sign_skey) do
    # DigestType is :none for ML-DSA as the algorithm handles hashing internally or takes raw message
    :crypto.sign(:mldsa87, :none, data, sign_skey)
  end

  @doc """
  Verifies a signature using the signing public key (ML-DSA-87).
  Returns true if valid, false otherwise.
  """
  def verify(data, signature, sign_pkey) do
    :crypto.verify(:mldsa87, :none, data, signature, sign_pkey)
  end

  @doc """
  Encapsulates a shared secret for the recipient using their public key (ML-KEM-1024).
  Returns {shared_secret, ciphertext}.
  """
  def encapsulate_secret(recipient_crypt_pkey) do
    :crypto.encapsulate_key(:mlkem1024, recipient_crypt_pkey)
  end

  @doc """
  Decapsulates a shared secret using the recipient's private key (ML-KEM-1024).
  Returns shared_secret.
  """
  def decapsulate_secret(ciphertext, recipient_crypt_skey) do
    :crypto.decapsulate_key(:mlkem1024, recipient_crypt_skey, ciphertext)
  end
end
