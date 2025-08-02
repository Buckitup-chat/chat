defmodule Chat.Schema.UserTest do
  use ChatWeb.DataCase

  alias Chat.Schema.User
  alias Chat.Repo
  alias Chat.Card

  describe "User schema" do
    test "writing and reading users from DB" do
      # Create a new card and convert to schema user
      card = Card.new("Test User", <<1, 2, 3, 4>>)
      user = User.from_card(card)

      # Save user to DB
      {:ok, saved_user} = Repo.insert(user)

      # Verify user was saved correctly
      assert saved_user.pub_key == <<1, 2, 3, 4>>
      assert saved_user.name == "Test User"

      # Retrieve user from DB
      retrieved_user = Repo.get(User, <<1, 2, 3, 4>>)

      # Verify retrieved user matches
      assert retrieved_user.pub_key == card.pub_key
      assert retrieved_user.name == card.name

      # Test hash virtual field
      assert retrieved_user[:hash] == Enigma.Hash.short_hash(retrieved_user.pub_key)

      # Test conversion back to card
      new_card = User.to_card(retrieved_user)
      assert new_card.name == card.name
      assert new_card.pub_key == card.pub_key
    end

    test "user with very long name can be saved" do
      # Create a long name (over 255 characters)
      long_name = String.duplicate("a", 300)
      card = Card.new(long_name, <<5, 6, 7, 8>>)
      user = User.from_card(card)

      # Save user to DB
      {:ok, saved_user} = Repo.insert(user)

      # Verify user was saved with long name
      assert saved_user.name == long_name
      assert byte_size(saved_user.name) == 300

      # Retrieve and verify
      retrieved_user = Repo.get(User, <<5, 6, 7, 8>>)
      assert retrieved_user.name == long_name
    end
  end
end
