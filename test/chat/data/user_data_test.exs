defmodule Chat.Data.UserDataTest do
  use ChatWeb.DataCase
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.{UserCard, UserStorage}
  alias Chat.Data.Types.Consts
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User
  alias Chat.Data.User.Validation
  alias Chat.Repo
  alias EnigmaPq

  defp signed_user_card(identity, attrs \\ %{}) do
    card =
      identity
      |> User.extract_pq_card()
      |> struct(Map.merge(%{deleted_flag: false, owner_timestamp: 1}, attrs))

    sign_b64 = Integrity.signature_payload(card) |> EnigmaPq.sign(identity.sign_skey)
    %{card | sign_b64: sign_b64}
  end

  describe "UserCard" do
    test "creates user card with valid hash" do
      # Generate real keys via User context
      identity = User.generate_pq_identity("Alice")

      # Extract card via User context
      card_struct = signed_user_card(identity)

      # Verify calculated fields
      expected_hash =
        identity.sign_pkey
        |> EnigmaPq.hash()
        |> UserHash.from_binary()

      assert card_struct.user_hash == expected_hash
      assert card_struct.name == "Alice"
      assert is_binary(card_struct.crypt_cert)

      # Insert using changeset (simulating what would happen in a real insert,
      # though we already have the struct, we might want to validate)
      # Usually we'd use the attrs from the struct or the struct itself if we trust it.
      # Let's convert to map for changeset to ensure validations pass.
      changeset =
        card_struct
        |> Map.from_struct()
        |> then(&UserCard.create_changeset(%UserCard{}, &1))

      assert changeset.valid?

      {:ok, card} = Repo.insert(changeset)
      assert card.user_hash == expected_hash
      assert card.name == "Alice"
    end

    test "soft-delete then undelete stays valid through user_card_validate/3" do
      identity = User.generate_pq_identity("SoftDelete")
      existing = signed_user_card(identity)

      softdelete =
        existing
        |> struct(%{
          deleted_flag: true,
          owner_timestamp: existing.owner_timestamp + 1
        })

      softdelete =
        %{
          softdelete
          | sign_b64: Integrity.signature_payload(softdelete) |> EnigmaPq.sign(identity.sign_skey)
        }

      softdelete_changeset =
        Validation.validate_user_card_update(existing, softdelete)

      assert softdelete_changeset.valid?, inspect(softdelete_changeset.errors)
      {:ok, softdeleted_card} = Ecto.Changeset.apply_action(softdelete_changeset, :validate)
      assert softdeleted_card.deleted_flag == true

      undelete =
        softdeleted_card
        |> struct(%{
          deleted_flag: false,
          owner_timestamp: softdeleted_card.owner_timestamp + 1
        })

      undelete_sign_b64 =
        undelete
        |> Integrity.signature_payload()
        |> EnigmaPq.sign(identity.sign_skey)

      undelete_changeset =
        Validation.validate_user_card_update(softdeleted_card, %{
          undelete
          | sign_b64: undelete_sign_b64
        })

      assert undelete_changeset.valid?, inspect(undelete_changeset.errors)
      {:ok, undeleted_card} = Ecto.Changeset.apply_action(undelete_changeset, :validate)
      refute undeleted_card.deleted_flag
      assert undeleted_card.owner_timestamp == softdeleted_card.owner_timestamp + 1
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
      fake_hash =
        "fake_key"
        |> EnigmaPq.hash()
        |> UserHash.from_binary()

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

    test "rejects card with tampered crypt_cert" do
      identity = User.generate_pq_identity("TamperedCryptCert")
      card = User.extract_pq_card(identity)

      # Tamper with crypt_cert directly
      tampered_cert = :crypto.strong_rand_bytes(byte_size(card.crypt_cert))
      bad_card = %{card | crypt_cert: tampered_cert}

      refute User.valid_card?(bad_card)
    end

    test "rejects card with tampered contact_cert" do
      identity = User.generate_pq_identity("TamperedContactCert")
      card = User.extract_pq_card(identity)

      # Tamper with contact_cert directly
      tampered_cert = :crypto.strong_rand_bytes(byte_size(card.contact_cert))
      bad_card = %{card | contact_cert: tampered_cert}

      refute User.valid_card?(bad_card)
    end

    test "rejects card with swapped crypt_cert and contact_cert" do
      identity = User.generate_pq_identity("SwappedCerts")
      card = User.extract_pq_card(identity)

      # Swap the certificates (both are valid signatures but for wrong keys)
      bad_card = %{card | crypt_cert: card.contact_cert, contact_cert: card.crypt_cert}

      refute User.valid_card?(bad_card)
    end

    test "rejects card with crypt_cert signed by wrong key" do
      identity = User.generate_pq_identity("WrongSignerCrypt")
      card = User.extract_pq_card(identity)

      # Generate a different signing key and sign crypt_pkey with it
      {_other_sign_pkey, other_sign_skey} = :crypto.generate_key(:mldsa87, [])
      wrong_crypt_cert = EnigmaPq.sign(card.crypt_pkey, other_sign_skey)
      bad_card = %{card | crypt_cert: wrong_crypt_cert}

      refute User.valid_card?(bad_card)
    end

    test "rejects card with contact_cert signed by wrong key" do
      identity = User.generate_pq_identity("WrongSignerContact")
      card = User.extract_pq_card(identity)

      # Generate a different signing key and sign contact_pkey with it
      {_other_sign_pkey, other_sign_skey} = :crypto.generate_key(:mldsa87, [])
      wrong_contact_cert = EnigmaPq.sign(card.contact_pkey, other_sign_skey)
      bad_card = %{card | contact_cert: wrong_contact_cert}

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
      card_struct = signed_user_card(identity)

      Repo.insert!(card_struct)

      # Insert Storage
      uuid = Ecto.UUID.generate()
      value = "some_encrypted_blob"

      # Create a storage struct with all required fields
      storage_struct = %UserStorage{
        user_hash: card_struct.user_hash,
        uuid: uuid,
        value_b64: value,
        deleted_flag: false,
        parent_sign_hash: nil,
        owner_timestamp: System.system_time(:second)
      }

      # Generate signature
      sign_b64 = Integrity.signature_payload(storage_struct) |> EnigmaPq.sign(identity.sign_skey)
      sign_hash_binary = :crypto.hash(:sha3_512, sign_b64)

      sign_hash =
        Consts.user_storage_sign_prefix() <> Base.encode16(sign_hash_binary, case: :lower)

      attrs = %{
        user_hash: card_struct.user_hash,
        uuid: uuid,
        value_b64: value,
        deleted_flag: false,
        parent_sign_hash: nil,
        owner_timestamp: storage_struct.owner_timestamp,
        sign_b64: sign_b64,
        sign_hash: sign_hash
      }

      changeset = UserStorage.create_changeset(%UserStorage{}, attrs)
      assert changeset.valid?, inspect(changeset.errors)

      {:ok, storage} = Repo.insert(changeset)
      assert storage.user_hash == card_struct.user_hash
      assert storage.value_b64 == value
    end
  end
end
