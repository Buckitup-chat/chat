defmodule Chat.Data.User do
  @moduledoc """
  User context for managing user data in Postgres
  """

  alias Chat.{Card, Identity}
  alias Chat.Data.Queries.UserQueries
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Types.Consts
  alias Enigma
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
    |> Map.merge(generate_contact_identity())
    |> Map.put(:name, name)
  end

  @doc """
  Extracts a UserCard (schema struct) from a PQ identity map.
  Computes the user_hash and signs the encryption key (certificate).
  """
  def extract_pq_card(%{
        sign_pkey: sign_pkey,
        sign_skey: sign_skey,
        crypt_pkey: crypt_pkey,
        contact_pkey: contact_pkey,
        name: name
      }) do
    user_hash =
      sign_pkey
      |> EnigmaPq.hash()
      |> then(&(Consts.user_hash_prefix() <> &1))

    crypt_cert = EnigmaPq.sign(crypt_pkey, sign_skey)
    contact_cert = EnigmaPq.sign(contact_pkey, sign_skey)

    %UserCard{
      user_hash: user_hash,
      sign_pkey: sign_pkey,
      contact_pkey: contact_pkey,
      contact_cert: contact_cert,
      crypt_pkey: crypt_pkey,
      crypt_cert: crypt_cert,
      name: name
    }
  end

  @doc """
  Verifies a UserCard's integrity.

  Checks:
  1. user_hash matches prefix + hash(sign_pkey)
  2. crypt_cert is a valid signature of crypt_pkey by sign_pkey
  3. contact_cert is a valid signature of contact_pkey by sign_pkey
  """
  def valid_card?(card) do
    case card do
      %UserCard{} = user_card ->
        verify_card_data(user_card.user_hash, user_card.sign_pkey, user_card)

      %{user_hash: hash, sign_pkey: sign_pkey} = card_data ->
        verify_card_data(hash, sign_pkey, card_data)
    end
  end

  defp verify_card_data(hash, sign_pkey, card_data) do
    expected_hash = Consts.user_hash_prefix() <> EnigmaPq.hash(sign_pkey)
    hash_valid? = hash == expected_hash

    crypt_cert_valid? =
      EnigmaPq.verify(card_data.crypt_pkey, card_data.crypt_cert, sign_pkey)

    contact_cert_valid? =
      EnigmaPq.verify(card_data.contact_pkey, card_data.contact_cert, sign_pkey)

    hash_valid? and crypt_cert_valid? and contact_cert_valid?
  end

  defp generate_contact_identity do
    {contact_skey, contact_pkey} = Enigma.generate_keys()

    %{
      contact_pkey: contact_pkey,
      contact_skey: contact_skey
    }
  end
end
