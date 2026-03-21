defmodule Chat.NetworkSynchronization.Electric.ShapeWriterTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.Integrity
  alias Chat.Data.User
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
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

  defp user_storage(user_hash, attrs \\ %{}) do
    Map.merge(
      %UserStorage{
        user_hash: user_hash,
        uuid: Ecto.UUID.generate(),
        value_b64: "dmFsdWU="
      },
      attrs
    )
  end

  describe "user_card" do
    test "insert writes a new row" do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)

      assert {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
      assert Repo.get(UserCard, card.user_hash) != nil
    end

    test "insert is idempotent — upserts on conflict" do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, signed_user_card(identity, %{name: "Bob"}))

      assert Repo.get(UserCard, card.user_hash).name == "Bob"
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

    test "delete marks the row as deleted" do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
      assert Repo.get(UserCard, card.user_hash) != nil

      deleted_card =
        signed_user_card_from(card, identity.sign_skey, %{
          deleted_flag: true,
          owner_timestamp: card.owner_timestamp + 1
        })

      {:ok, _} =
        ShapeWriter.write(
          :user_card,
          :delete,
          deleted_card
        )

      assert Repo.get(UserCard, card.user_hash).deleted_flag == true
    end

    test "delete of missing row succeeds" do
      identity = User.generate_pq_identity("Alice")

      assert {:ok, _} =
               ShapeWriter.write(
                 :user_card,
                 :delete,
                 signed_user_card(identity, %{deleted_flag: true})
               )
    end
  end

  describe "user_storage" do
    # user_storage has a FK to user_cards — the card must exist first
    setup do
      identity = User.generate_pq_identity("Alice")
      card = signed_user_card(identity)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)

      {:ok, user_hash: card.user_hash}
    end

    test "insert writes a new row", %{user_hash: user_hash} do
      row = user_storage(user_hash)
      assert {:ok, _} = ShapeWriter.write(:user_storage, :insert, row)

      stored = Repo.get_by(UserStorage, user_hash: user_hash, uuid: row.uuid)
      assert stored.value_b64 == "dmFsdWU="
    end

    test "insert is idempotent — upserts on conflict", %{user_hash: user_hash} do
      uuid = Ecto.UUID.generate()
      row = user_storage(user_hash, %{uuid: uuid})

      {:ok, _} = ShapeWriter.write(:user_storage, :insert, row)
      {:ok, _} = ShapeWriter.write(:user_storage, :insert, %{row | value_b64: "dXBkYXRlZA=="})

      stored = Repo.get_by(UserStorage, user_hash: user_hash, uuid: uuid)
      assert stored.value_b64 == "dXBkYXRlZA=="
    end

    test "delete removes the row", %{user_hash: user_hash} do
      row = user_storage(user_hash)
      {:ok, _} = ShapeWriter.write(:user_storage, :insert, row)
      {:ok, _} = ShapeWriter.write(:user_storage, :delete, row)

      assert Repo.get_by(UserStorage, user_hash: user_hash, uuid: row.uuid) == nil
    end
  end
end
