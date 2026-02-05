defmodule Chat.Data.User do
  @moduledoc """
  User context for managing user data in Postgres
  """

  alias Chat.Card
  alias Chat.Data.Queries.UserQueries
  alias Chat.Identity
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Types.Consts
  alias EnigmaPq

  @doc """
  Registers a user from an Identity or Card
  """
  def register(%Identity{} = identity) do
    identity |> Card.from_identity() |> register()
  end

  def register(%Card{} = card) do
    UserQueries.insert_card(card)
    card.pub_key
  end

  @doc """
  Gets all users from Postgres
  """
  def all do
    UserQueries.list_all()
    |> Map.new(fn user -> {user.pub_key, Chat.Data.Schemas.User.to_card(user)} end)
  end

  @doc """
  Gets a user by public key from Postgres
  """
  def get(pub_key) do
    case UserQueries.get_by_pub_key(pub_key) do
      nil -> nil
      user -> Chat.Data.Schemas.User.to_card(user)
    end
  end

  @doc """
  Removes a user by public key from Postgres
  """
  def remove(pub_key) do
    UserQueries.delete_by_pub_key(pub_key)
  end

  @doc """
  Legacy function maintained for compatibility.
  In Postgres-only mode, no need to wait for writes.
  """
  def await_saved(_) do
    :ok
  end

  @doc """
  Creates a user directly in Postgres.
  Electric will automatically detect and sync the change.
  """
  def create(attrs) do
    UserQueries.create(attrs)
  end

  @doc """
  Generates a new Post-Quantum Identity (map) with a name.
  Uses EnigmaPq to generate keys.
  """
  def generate_pq_identity(name) do
    EnigmaPq.generate_identity()
    |> Map.put(:name, name)
  end

  @doc """
  Extracts a UserCard (schema struct) from a PQ identity map.
  Computes the user_hash and signs the encryption key (certificate).
  """
  def extract_pq_card(%{sign_pkey: sign_pkey, sign_skey: sign_skey, crypt_pkey: crypt_pkey, name: name}) do
    raw_hash = EnigmaPq.hash(sign_pkey)
    user_hash = Consts.user_hash_prefix() <> raw_hash

    cert = EnigmaPq.sign(crypt_pkey, sign_skey)

    %UserCard{
      user_hash: user_hash,
      sign_pkey: sign_pkey,
      crypt_pkey: crypt_pkey,
      crypt_pkey_cert: cert,
      name: name
    }
  end

  @doc """
  Verifies a UserCard's integrity.
  Checks:
  1. user_hash matches prefix + hash(sign_pkey)
  2. crypt_pkey_cert is a valid signature of crypt_pkey by sign_pkey
  """
  def valid_card?(%UserCard{user_hash: hash, sign_pkey: sign_pkey, crypt_pkey: crypt_pkey, crypt_pkey_cert: cert}) do
    verify_card_data(hash, sign_pkey, crypt_pkey, cert)
  end

  def valid_card?(%{user_hash: hash, sign_pkey: sign_pkey, crypt_pkey: crypt_pkey, crypt_pkey_cert: cert}) do
    verify_card_data(hash, sign_pkey, crypt_pkey, cert)
  end

  defp verify_card_data(hash, sign_pkey, crypt_pkey, cert) do
    expected_hash = Consts.user_hash_prefix() <> EnigmaPq.hash(sign_pkey)
    hash_valid? = hash == expected_hash

    cert_valid? = EnigmaPq.verify(crypt_pkey, cert, sign_pkey)

    hash_valid? and cert_valid?
  end
end
