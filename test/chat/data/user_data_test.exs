defmodule Chat.Data.UserDataTest do
  use ChatWeb.DataCase
  alias Chat.Data.Schemas.{UserCard, UserStorage}
  alias Chat.Repo
  alias EnigmaPq
  alias Chat.Data.Types.Consts
  alias Chat.Data.User

  describe "UserCard" do
    test "creates user card with valid hash" do
      # Generate real keys via User context
      identity = User.generate_pq_identity("Alice")

      # Extract card via User context
      card_struct = User.extract_pq_card(identity)

      # Verify calculated fields
      expected_hash = Consts.user_hash_prefix() <> EnigmaPq.hash(identity.sign_pkey)
      assert card_struct.user_hash == expected_hash
      assert card_struct.name == "Alice"
      assert is_binary(card_struct.crypt_cert)

      # Insert using changeset (simulating what would happen in a real insert,
      # though we already have the struct, we might want to validate)
      # Usually we'd use the attrs from the struct or the struct itself if we trust it.
      # Let's convert to map for changeset to ensure validations pass.
      attrs = Map.from_struct(card_struct)

      changeset = UserCard.create_changeset(%UserCard{}, attrs)
      assert changeset.valid?

      {:ok, card} = Repo.insert(changeset)
      assert card.user_hash == expected_hash
      assert card.name == "Alice"
    end

    test "verifies valid card" do
      identity = User.generate_pq_identity("ValidUser")
      card = User.extract_pq_card(identity)
      assert User.valid_card?(card)
    end

    test "rejects card with invalid hash" do
      identity = User.generate_pq_identity("HackerHash")
      card = User.extract_pq_card(identity)

      # Tamper with hash
      fake_hash = Consts.user_hash_prefix() <> EnigmaPq.hash("fake_key")
      bad_card = %{card | user_hash: fake_hash}

      refute User.valid_card?(bad_card)
    end

    test "rejects card with invalid certificate" do
      identity = User.generate_pq_identity("HackerCert")
      card = User.extract_pq_card(identity)

      # Tamper with crypt key (cert won't match)
      bad_card = %{card | crypt_pkey: "tampered_key"}

      refute User.valid_card?(bad_card)
    end

    test "rejects card with invalid prefix in hash" do
      identity = User.generate_pq_identity("BadPrefix")
      card = User.extract_pq_card(identity)

      # Wrong prefix
      bad_hash = Consts.dialog_hash_prefix() <> EnigmaPq.hash(card.sign_pkey)
      bad_card = %{card | user_hash: bad_hash}

      refute User.valid_card?(bad_card)
    end

    test "fails with invalid user hash prefix" do
      # Use dialog prefix as invalid prefix for user hash
      bad_prefix = Consts.dialog_hash_prefix()
      raw_hash = :crypto.strong_rand_bytes(64)
      bad_hash = bad_prefix <> raw_hash

      {sign_pkey, sign_skey} = :crypto.generate_key(:mldsa87, [])
      {contact_pkey, _contact_skey} = :crypto.generate_key(:mldsa44, [])
      {crypt_pkey, _crypt_skey} = :crypto.generate_key(:mlkem1024, [])

      contact_cert = EnigmaPq.sign(contact_pkey, sign_skey)
      crypt_cert = EnigmaPq.sign(crypt_pkey, sign_skey)

      attrs = %{
        user_hash: bad_hash,
        sign_pkey: sign_pkey,
        contact_pkey: contact_pkey,
        contact_cert: contact_cert,
        crypt_pkey: crypt_pkey,
        crypt_cert: crypt_cert,
        name: "Bob"
      }

      # The cast in UserHash type should error or the DB constraint will fail
      # Our custom type `cast` checks for 0x01 prefix
      changeset = UserCard.create_changeset(%UserCard{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).user_hash
    end
  end

  describe "UserStorage" do
    test "creates storage for existing user" do
      # Setup User via Context
      identity = User.generate_pq_identity("Charlie")
      card_struct = User.extract_pq_card(identity)

      Repo.insert!(card_struct)

      # Insert Storage
      uuid = Ecto.UUID.generate()
      value = "some_encrypted_blob"

      attrs = %{
        user_hash: card_struct.user_hash,
        uuid: uuid,
        value: value
      }

      changeset = UserStorage.changeset(%UserStorage{}, attrs)
      assert changeset.valid?

      {:ok, storage} = Repo.insert(changeset)
      assert storage.user_hash == card_struct.user_hash
      assert storage.value == value
    end
  end
end
