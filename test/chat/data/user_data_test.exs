defmodule Chat.Data.UserDataTest do
  use ChatWeb.DataCase, async: true
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.{UserCard, UserStorage}
  alias Chat.Data.Types.Consts
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User
  alias Chat.Data.User.Validation
  alias Chat.Repo
  alias EnigmaPq

  describe "UserCard" do
    test "creates user card with valid hash" do
      identity = User.generate_pq_identity("Alice")
      card_struct = signed_user_card(identity)
      expected_hash = expected_user_hash(identity)

      assert card_struct.user_hash == expected_hash
      assert card_struct.name == "Alice"
      assert is_binary(card_struct.crypt_cert)

      {:ok, card} = insert_via_changeset(card_struct)
      assert card.user_hash == expected_hash
      assert card.name == "Alice"
    end

    test "soft-delete then undelete stays valid through user_card_validate/3" do
      identity = User.generate_pq_identity("SoftDelete")
      existing = signed_user_card(identity)

      softdelete =
        resign_card(existing, identity,
          deleted_flag: true,
          owner_timestamp: existing.owner_timestamp + 1
        )

      softdelete_changeset = Validation.validate_user_card_update(existing, softdelete)

      assert softdelete_changeset.valid?, inspect(softdelete_changeset.errors)
      {:ok, softdeleted_card} = Ecto.Changeset.apply_action(softdelete_changeset, :validate)
      assert softdeleted_card.deleted_flag == true

      undelete =
        resign_card(softdeleted_card, identity,
          deleted_flag: false,
          owner_timestamp: softdeleted_card.owner_timestamp + 1
        )

      undelete_changeset = Validation.validate_user_card_update(softdeleted_card, undelete)

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
      fake_hash = "fake_key" |> EnigmaPq.hash() |> UserHash.from_binary()

      refute User.valid_card?(%{card | user_hash: fake_hash})
    end

    test "rejects card with invalid certificate" do
      identity = User.generate_pq_identity("HackerCert")
      card = User.extract_pq_card(identity)

      refute User.valid_card?(%{card | crypt_pkey: "tampered_key"})
    end

    test "rejects card with tampered crypt_cert" do
      identity = User.generate_pq_identity("TamperedCryptCert")
      card = User.extract_pq_card(identity)
      tampered_cert = :crypto.strong_rand_bytes(byte_size(card.crypt_cert))

      refute User.valid_card?(%{card | crypt_cert: tampered_cert})
    end

    test "rejects card with tampered contact_cert" do
      identity = User.generate_pq_identity("TamperedContactCert")
      card = User.extract_pq_card(identity)
      tampered_cert = :crypto.strong_rand_bytes(byte_size(card.contact_cert))

      refute User.valid_card?(%{card | contact_cert: tampered_cert})
    end

    test "rejects card with swapped crypt_cert and contact_cert" do
      identity = User.generate_pq_identity("SwappedCerts")
      card = User.extract_pq_card(identity)

      refute User.valid_card?(%{
               card
               | crypt_cert: card.contact_cert,
                 contact_cert: card.crypt_cert
             })
    end

    test "rejects card with crypt_cert signed by wrong key" do
      identity = User.generate_pq_identity("WrongSignerCrypt")
      card = User.extract_pq_card(identity)
      wrong_cert = sign_with_other_key(card.crypt_pkey)

      refute User.valid_card?(%{card | crypt_cert: wrong_cert})
    end

    test "rejects card with contact_cert signed by wrong key" do
      identity = User.generate_pq_identity("WrongSignerContact")
      card = User.extract_pq_card(identity)
      wrong_cert = sign_with_other_key(card.contact_pkey)

      refute User.valid_card?(%{card | contact_cert: wrong_cert})
    end

    test "rejects card with invalid prefix in hash" do
      identity = User.generate_pq_identity("BadPrefix")
      card = User.extract_pq_card(identity)
      bad_card = %{card | user_hash: Consts.dialog_hash_prefix() <> EnigmaPq.hash(card.sign_pkey)}

      refute User.valid_card?(bad_card)
    end

    test "fails with invalid user hash prefix" do
      attrs = card_attrs_with_bad_hash_prefix()

      changeset = UserCard.create_changeset(%UserCard{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).user_hash
    end
  end

  describe "UserStorage" do
    test "creates storage for existing user" do
      identity = User.generate_pq_identity("Charlie")
      card_struct = signed_user_card(identity)
      Repo.insert!(card_struct)

      attrs =
        signed_storage_attrs(identity, card_struct.user_hash, value_b64: "some_encrypted_blob")

      changeset = UserStorage.create_changeset(%UserStorage{}, attrs)
      assert changeset.valid?, inspect(changeset.errors)

      {:ok, storage} = Repo.insert(changeset)
      assert storage.user_hash == card_struct.user_hash
      assert storage.value_b64 == "some_encrypted_blob"
    end

    defp signed_storage_attrs(identity, user_hash, opts) do
      storage = %UserStorage{
        user_hash: user_hash,
        uuid: Keyword.get(opts, :uuid, Ecto.UUID.generate()),
        value_b64: Keyword.fetch!(opts, :value_b64),
        deleted_flag: false,
        parent_sign_hash: nil,
        owner_timestamp: System.system_time(:second)
      }

      sign_b64 = Integrity.signature_payload(storage) |> EnigmaPq.sign(identity.sign_skey)
      sign_hash_binary = :crypto.hash(:sha3_512, sign_b64)

      sign_hash =
        Consts.user_storage_sign_prefix() <> Base.encode16(sign_hash_binary, case: :lower)

      Map.from_struct(storage) |> Map.merge(%{sign_b64: sign_b64, sign_hash: sign_hash})
    end
  end

  defp expected_user_hash(identity) do
    identity.sign_pkey |> EnigmaPq.hash() |> UserHash.from_binary()
  end

  defp insert_via_changeset(card_struct) do
    card_struct
    |> Map.from_struct()
    |> then(&UserCard.create_changeset(%UserCard{}, &1))
    |> Repo.insert()
  end

  defp sign_with_other_key(payload) do
    {_pkey, skey} = :crypto.generate_key(:mldsa87, [])
    EnigmaPq.sign(payload, skey)
  end

  defp card_attrs_with_bad_hash_prefix do
    {sign_pkey, sign_skey} = :crypto.generate_key(:mldsa87, [])
    {contact_pkey, _} = :crypto.generate_key(:mldsa44, [])
    {crypt_pkey, _} = :crypto.generate_key(:mlkem1024, [])

    %{
      user_hash: Consts.dialog_hash_prefix() <> :crypto.strong_rand_bytes(64),
      sign_pkey: sign_pkey,
      contact_pkey: contact_pkey,
      contact_cert: EnigmaPq.sign(contact_pkey, sign_skey),
      crypt_pkey: crypt_pkey,
      crypt_cert: EnigmaPq.sign(crypt_pkey, sign_skey),
      name: "Bob"
    }
  end

  defp signed_user_card(identity, attrs \\ %{}) do
    card =
      identity
      |> User.extract_pq_card()
      |> struct(Map.merge(%{deleted_flag: false, owner_timestamp: 1}, attrs))

    sign_b64 = Integrity.signature_payload(card) |> EnigmaPq.sign(identity.sign_skey)
    %{card | sign_b64: sign_b64}
  end

  defp resign_card(card, identity, attrs) do
    updated = struct(card, attrs)
    sign_b64 = Integrity.signature_payload(updated) |> EnigmaPq.sign(identity.sign_skey)
    %{updated | sign_b64: sign_b64}
  end
end
