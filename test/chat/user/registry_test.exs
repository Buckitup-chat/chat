defmodule Chat.User.RegistryTest do
  use ExUnit.Case, async: false

  alias Chat.Card
  alias Chat.Db
  alias Chat.Db.ChangeTracker
  alias Chat.User.Registry

  setup do
    on_exit(fn ->
      [
        <<10, 11, 12, 13>>,
        <<20, 21, 22, 23>>,
        <<30, 31, 32, 33>>,
        <<40, 41, 42, 43>>,
        <<50, 51, 52, 53>>,
        <<60, 61, 62, 63>>,
        <<99, 99, 99, 99>>
      ]
      |> Enum.each(&Db.delete({:users, &1}))
    end)
  end

  describe "Registry.enlist/1" do
    test "saves user to CubDB" do
      card = Card.new("CubDB User", <<10, 11, 12, 13>>)
      pub_key = Registry.enlist(card)
      Registry.await_saved(pub_key)

      assert pub_key == <<10, 11, 12, 13>>

      saved = Registry.one(pub_key)
      assert saved.name == "CubDB User"
      assert saved.pub_key == <<10, 11, 12, 13>>
    end

    test "updates existing user" do
      card1 = Card.new("Original Name", <<20, 21, 22, 23>>)
      pub_key = Registry.enlist(card1)
      Registry.await_saved(pub_key)

      card2 = Card.new("Updated Name", <<20, 21, 22, 23>>)
      Registry.enlist(card2)
      ChangeTracker.await()

      saved = Registry.one(pub_key)
      assert saved.name == "Updated Name"
    end
  end

  describe "Registry.all/0" do
    test "retrieves all users" do
      card1 = Card.new("User One", <<30, 31, 32, 33>>)
      card2 = Card.new("User Two", <<40, 41, 42, 43>>)

      pk1 = Registry.enlist(card1)
      pk2 = Registry.enlist(card2)
      Registry.await_saved([pk1, pk2])

      users = Registry.all()

      assert users[card1.pub_key].name == "User One"
      assert users[card2.pub_key].name == "User Two"
    end
  end

  describe "Registry.one/1" do
    test "retrieves a single user" do
      card = Card.new("Single User", <<50, 51, 52, 53>>)
      pub_key = Registry.enlist(card)
      Registry.await_saved(pub_key)

      user = Registry.one(pub_key)

      assert user.name == "Single User"
      assert user.pub_key == <<50, 51, 52, 53>>
    end

    test "returns nil for non-existent user" do
      assert Registry.one(<<99, 99, 99, 99>>) == nil
    end
  end

  describe "Registry.remove/1" do
    test "removes user" do
      card = Card.new("To Be Removed", <<60, 61, 62, 63>>)
      pub_key = Registry.enlist(card)
      Registry.await_saved(pub_key)

      assert Registry.one(pub_key) != nil
      Registry.remove(pub_key)
      ChangeTracker.await()
      assert Registry.one(pub_key) == nil
    end
  end
end
