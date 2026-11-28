defmodule Chat.Test.UserStorageFixtures do
  @moduledoc """
  Signed `user_storage` rows and their archived `user_storage_versions`, shared by the
  `user_storage_versioning_*` tests.
  """

  import Chat.Test.ReviewFixtures, only: [sign_with_hash: 3]
  import Ecto.Query

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Schemas.UserStorageVersion
  alias Chat.Data.Types.UserHash
  alias Chat.Data.Types.UserStorageSignHash
  alias Chat.Data.User
  alias Chat.Repo

  @doc "Setup: inserts a signed user card and returns `card`, `identity` and `user_hash`."
  def user_with_card(_ctx) do
    identity = EnigmaPq.generate_identity()
    user_hash = identity.sign_pkey |> EnigmaPq.hash() |> UserHash.from_binary()

    card_attrs = %{
      user_hash: user_hash,
      sign_pkey: identity.sign_pkey,
      contact_pkey: identity.crypt_pkey,
      contact_cert: <<1, 2, 3>>,
      crypt_pkey: identity.crypt_pkey,
      crypt_cert: <<4, 5, 6>>,
      name: "Test User",
      deleted_flag: false,
      owner_timestamp: System.system_time(:second)
    }

    sign_b64 =
      %UserCard{}
      |> struct(card_attrs)
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(identity.sign_skey)

    card =
      %UserCard{}
      |> UserCard.create_changeset(Map.put(card_attrs, :sign_b64, sign_b64))
      |> Repo.insert!()

    %{card: card, identity: identity, user_hash: user_hash}
  end

  @doc "Unsaved `UserStorage` signed by `identity`; `attrs` override the defaults."
  def signed_storage(identity, user_hash, attrs \\ %{}) do
    %UserStorage{
      user_hash: user_hash,
      uuid: Ecto.UUID.generate(),
      value_b64: "test value",
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: System.system_time(:second)
    }
    |> struct(attrs)
    |> sign_with_hash(identity.sign_skey, &UserStorageSignHash.from_binary/1)
  end

  @doc "Random sign hash that matches no stored row."
  def random_storage_sign_hash,
    do: :crypto.strong_rand_bytes(64) |> UserStorageSignHash.from_binary()

  @doc "Inserts `storage` directly through `UserStorage.create_changeset/2`."
  def insert_storage!(storage) do
    %UserStorage{}
    |> UserStorage.create_changeset(Map.from_struct(storage))
    |> Repo.insert!()
  end

  @doc "Inserts `storage` through the `Chat.Data.User.insert_storage/1` context upsert."
  def insert_storage_via_context!(storage) do
    %UserStorage{}
    |> UserStorage.create_changeset(Map.from_struct(storage))
    |> User.insert_storage()
  end

  @doc "Signs, inserts and archives a storage row; returns the inserted row."
  def insert_and_archive(identity, user_hash, attrs) do
    identity
    |> signed_storage(user_hash, attrs)
    |> insert_storage!()
    |> tap(&archive_storage!/1)
  end

  @doc "Archives `storage` as a `UserStorageVersion` row."
  def archive_storage!(storage) do
    %UserStorageVersion{}
    |> UserStorageVersion.changeset(%{
      user_hash: storage.user_hash,
      uuid: storage.uuid,
      sign_hash: storage.sign_hash,
      value_b64: storage.value_b64,
      deleted_flag: storage.deleted_flag,
      parent_sign_hash: storage.parent_sign_hash,
      owner_timestamp: storage.owner_timestamp,
      sign_b64: storage.sign_b64
    })
    |> Repo.insert!()
  end

  @doc "Current `user_storage` row for `user_hash` + `uuid`."
  def get_storage(user_hash, uuid), do: Repo.get_by(UserStorage, user_hash: user_hash, uuid: uuid)

  @doc "Archived version of `user_hash` + `uuid` with `sign_hash`, or `nil`."
  def get_version(user_hash, uuid, sign_hash) do
    Repo.get_by(UserStorageVersion, user_hash: user_hash, uuid: uuid, sign_hash: sign_hash)
  end

  @doc "Number of archived versions of `user_hash` + `uuid`."
  def count_versions(user_hash, uuid) do
    from(v in UserStorageVersion, where: v.user_hash == ^user_hash and v.uuid == ^uuid)
    |> Repo.aggregate(:count)
  end
end
