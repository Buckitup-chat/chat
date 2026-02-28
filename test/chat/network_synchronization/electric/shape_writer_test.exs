defmodule Chat.NetworkSynchronization.Electric.ShapeWriterTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.Repo

  # Valid UserHash: 65-byte binary with prefix byte <<1>>
  @user_hash <<1, 0::512>>

  defp user_card(attrs \\ %{}) do
    Map.merge(
      %UserCard{
        user_hash: @user_hash,
        name: "Alice",
        sign_pkey: "spk",
        contact_pkey: "cpk",
        contact_cert: "cc",
        crypt_pkey: "cryptpk",
        crypt_cert: "cryptcc"
      },
      attrs
    )
  end

  defp user_storage(attrs \\ %{}) do
    Map.merge(
      %UserStorage{
        user_hash: @user_hash,
        uuid: Ecto.UUID.generate(),
        value_b64: "dmFsdWU="
      },
      attrs
    )
  end

  describe "user_card" do
    test "insert writes a new row" do
      card = user_card()
      assert {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
      assert Repo.get(UserCard, @user_hash) != nil
    end

    test "insert is idempotent — upserts on conflict" do
      card = user_card()
      {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
      {:ok, _} = ShapeWriter.write(:user_card, :insert, %{card | name: "Bob"})

      assert Repo.get(UserCard, @user_hash).name == "Bob"
    end

    test "update overwrites existing row" do
      {:ok, _} = ShapeWriter.write(:user_card, :insert, user_card())
      {:ok, _} = ShapeWriter.write(:user_card, :update, user_card(%{name: "Carol"}))

      assert Repo.get(UserCard, @user_hash).name == "Carol"
    end

    test "delete removes the row" do
      {:ok, _} = ShapeWriter.write(:user_card, :insert, user_card())
      assert Repo.get(UserCard, @user_hash) != nil

      {:ok, _} = ShapeWriter.write(:user_card, :delete, user_card())
      assert Repo.get(UserCard, @user_hash) == nil
    end

    test "delete of missing row succeeds" do
      assert {:ok, _} = ShapeWriter.write(:user_card, :delete, user_card())
    end
  end

  describe "user_storage" do
    # user_storage has a FK to user_cards — the card must exist first
    setup do
      {:ok, _} = ShapeWriter.write(:user_card, :insert, user_card())
      :ok
    end

    test "insert writes a new row" do
      row = user_storage()
      assert {:ok, _} = ShapeWriter.write(:user_storage, :insert, row)

      stored = Repo.get_by(UserStorage, user_hash: @user_hash, uuid: row.uuid)
      assert stored.value_b64 == "dmFsdWU="
    end

    test "insert is idempotent — upserts on conflict" do
      uuid = Ecto.UUID.generate()
      row = user_storage(%{uuid: uuid})

      {:ok, _} = ShapeWriter.write(:user_storage, :insert, row)
      {:ok, _} = ShapeWriter.write(:user_storage, :insert, %{row | value_b64: "dXBkYXRlZA=="})

      stored = Repo.get_by(UserStorage, user_hash: @user_hash, uuid: uuid)
      assert stored.value_b64 == "dXBkYXRlZA=="
    end

    test "delete removes the row" do
      row = user_storage()
      {:ok, _} = ShapeWriter.write(:user_storage, :insert, row)
      {:ok, _} = ShapeWriter.write(:user_storage, :delete, row)

      assert Repo.get_by(UserStorage, user_hash: @user_hash, uuid: row.uuid) == nil
    end
  end
end
