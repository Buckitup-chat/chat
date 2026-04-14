defmodule Chat.NetworkSynchronization.Electric.ShapeWriterTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Types.UserStorageSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.Repo

  defp signed_user_card(identity, attrs \\ %{}) do
    card =
      identity
      |> User.extract_pq_card()
      |> struct(attrs)

    sign_b64 =
      card
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(identity.sign_skey)

    %{card | sign_b64: sign_b64}
  end

  defp signed_user_card_from(card, sign_skey, attrs \\ %{}) do
    updated_card = struct(card, attrs)

    sign_b64 =
      updated_card
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(sign_skey)

    %{updated_card | sign_b64: sign_b64}
  end

  defp signed_user_storage(identity, user_hash, attrs \\ %{}) do
    storage =
      %UserStorage{
        user_hash: user_hash,
        uuid: Ecto.UUID.generate(),
        value_b64: "dmFsdWU=",
        deleted_flag: false,
        owner_timestamp: System.os_time(:millisecond)
      }
      |> struct(attrs)

    sign_b64 =
      storage
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(identity.sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> UserStorageSignHash.from_binary()

    %{storage | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  describe "user_card" do
    test "insert writes a new row" do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)

      assert {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
      assert Repo.get(UserCard, card.user_hash) != nil
    end

    test "insert with newer timestamp upserts on conflict" do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

      newer_card =
        signed_user_card(identity, %{name: "Bob", owner_timestamp: card.owner_timestamp + 1})

      {:ok, _} = ShapeWriter.write(:user_card, :insert, newer_card)

      assert Repo.get(UserCard, card.user_hash).name == "Bob"
    end

    test "insert with same timestamp is skipped — no WAL ping-pong" do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

      same_ts_card = signed_user_card(identity, %{name: "Bob"})
      {:ok, _} = ShapeWriter.write(:user_card, :insert, same_ts_card)

      assert Repo.get(UserCard, card.user_hash).name == "Alice"
    end

    test "update overwrites existing row" do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

      updated_card =
        signed_user_card_from(card, identity.sign_skey, %{
          name: "Carol",
          owner_timestamp: card.owner_timestamp + 1
        })

      {:ok, _} = ShapeWriter.write(:user_card, :update, updated_card)

      assert Repo.get(UserCard, card.user_hash).name == "Carol"
    end

    test "update does not change keys, only name" do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

      {:ok, _} =
        ShapeWriter.write(
          :user_card,
          :update,
          signed_user_card_from(card, identity.sign_skey, %{
            name: "NewName",
            owner_timestamp: card.owner_timestamp + 1
          })
        )

      updated = Repo.get(UserCard, card.user_hash)
      assert updated.name == "NewName"
      assert updated.sign_pkey == card.sign_pkey
    end

  end

  describe "user_storage" do
    # user_storage has a FK to user_cards — the card must exist first
    setup do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

      {:ok, user_hash: card.user_hash, identity: identity}
    end

    test "insert writes a new row", %{user_hash: user_hash, identity: identity} do
      row = signed_user_storage(identity, user_hash)
      assert {:ok, _} = ShapeWriter.write(:user_storage, :insert, row)

      stored = Repo.get_by(UserStorage, user_hash: user_hash, uuid: row.uuid)
      assert stored.value_b64 == "dmFsdWU="
    end

    test "insert is idempotent — upserts on conflict", %{user_hash: user_hash, identity: identity} do
      uuid = Ecto.UUID.generate()
      row = signed_user_storage(identity, user_hash, %{uuid: uuid})

      {:ok, _} = ShapeWriter.write(:user_storage, :insert, row)

      updated_row =
        signed_user_storage(identity, user_hash, %{
          uuid: uuid,
          value_b64: "dXBkYXRlZA==",
          owner_timestamp: row.owner_timestamp + 1
        })

      {:ok, _} = ShapeWriter.write(:user_storage, :insert, updated_row)

      stored = Repo.get_by(UserStorage, user_hash: user_hash, uuid: uuid)
      assert stored.value_b64 == "dXBkYXRlZA=="
    end

    test "soft delete marks the row as deleted", %{user_hash: user_hash, identity: identity} do
      row = signed_user_storage(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:user_storage, :insert, row)

      deleted_row =
        signed_user_storage(identity, user_hash, %{
          uuid: row.uuid,
          deleted_flag: true,
          owner_timestamp: row.owner_timestamp + 1
        })

      {:ok, _} = ShapeWriter.write(:user_storage, :update, deleted_row)

      stored = Repo.get_by(UserStorage, user_hash: user_hash, uuid: row.uuid)
      assert stored.deleted_flag == true
    end
  end
end
