defmodule Chat.Data.User do
  @moduledoc """
  User context for managing user data in Postgres
  """

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.User.Versioning
  alias Enigma
  alias EnigmaPq

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
      |> Chat.Data.Types.UserHash.from_binary()

    crypt_cert = EnigmaPq.sign(crypt_pkey, sign_skey)
    contact_cert = EnigmaPq.sign(contact_pkey, sign_skey)

    card = %UserCard{
      user_hash: user_hash,
      sign_pkey: sign_pkey,
      contact_pkey: contact_pkey,
      contact_cert: contact_cert,
      crypt_pkey: crypt_pkey,
      crypt_cert: crypt_cert,
      name: name,
      deleted_flag: false,
      owner_timestamp: System.system_time(:second)
    }

    sign_b64 =
      card
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(sign_skey)

    %{card | sign_b64: sign_b64}
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

  @doc """
  Gets a UserCard by user_hash from Postgres
  """
  def get_card(user_hash) do
    repo().get(UserCard, user_hash)
  end

  @doc """
  Inserts a UserCard with upsert semantics.
  On conflict, updates only if the incoming timestamp is newer.
  """
  def upsert_card(changeset) do
    repo().insert(changeset,
      on_conflict: user_card_upsert_query(),
      conflict_target: :user_hash,
      allow_stale: true
    )
  end

  @doc """
  Updates an existing UserCard changeset.
  """
  def update_card(changeset) do
    repo().update(changeset)
  end

  @doc """
  Gets a UserStorage record by user_hash and uuid.
  """
  def get_storage(user_hash, uuid) do
    repo().get_by(UserStorage, user_hash: user_hash, uuid: uuid)
  end

  @doc """
  Inserts a new UserStorage record.
  """
  def insert_storage(changeset) do
    repo().insert(changeset)
  end

  @doc """
  Inserts a UserStorage record when one with the same key already exists.
  Delegates to Versioning to handle timestamp-based conflict resolution.
  """
  def insert_storage_with_conflict(existing, new_storage) do
    Versioning.handle_insert_with_conflict(repo(), existing, new_storage)
  end

  @doc """
  Updates a UserStorage record with versioning.
  Archives the old version and applies the update based on timestamps.
  """
  def update_storage_with_versioning(existing, new_storage) do
    Versioning.handle_update_with_versioning(repo(), existing, new_storage)
  end

  defp user_card_upsert_query do
    from(c in UserCard,
      update: [
        set: [
          sign_pkey: fragment("EXCLUDED.sign_pkey"),
          contact_pkey: fragment("EXCLUDED.contact_pkey"),
          contact_cert: fragment("EXCLUDED.contact_cert"),
          crypt_pkey: fragment("EXCLUDED.crypt_pkey"),
          crypt_cert: fragment("EXCLUDED.crypt_cert"),
          name: fragment("EXCLUDED.name"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64")
        ]
      ],
      where: is_nil(c.owner_timestamp) or c.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end

  defp verify_card_data(hash, sign_pkey, card_data) do
    expected_hash =
      sign_pkey
      |> EnigmaPq.hash()
      |> Chat.Data.Types.UserHash.from_binary()

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
