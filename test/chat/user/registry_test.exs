defmodule Chat.User.RegistryTest do
  use ChatWeb.DataCase

  alias Chat.Card
  alias Chat.Repo
  alias Chat.Data.Schemas.User
  alias Chat.User.Registry
  
  describe "Registry.enlist/1" do
    test "saves user to Postgres" do
      # Create a test card
      card = Card.new("Postgres Storage User", <<10, 11, 12, 13>>)
      
      # Enlist the card (should save to Postgres)
      pub_key = Registry.enlist(card)
      
      # Verify it was saved in Postgres
      postgres_user = Repo.get(User, pub_key)
      assert postgres_user.name == "Postgres Storage User"
      assert postgres_user.pub_key == <<10, 11, 12, 13>>
    end
    
    test "updates existing user in Postgres" do
      # Create initial card
      card1 = Card.new("Original Name", <<20, 21, 22, 23>>)
      Registry.enlist(card1)
      
      # Create updated card with same pub_key but different name
      card2 = Card.new("Updated Name", <<20, 21, 22, 23>>)
      Registry.enlist(card2)
      
      # Verify it was updated in Postgres
      postgres_user = Repo.get(User, card1.pub_key)
      assert postgres_user.name == "Updated Name"
    end
  end

  describe "Registry.all/0" do
    test "retrieves all users from Postgres" do
      # Create multiple users
      card1 = Card.new("User One", <<30, 31, 32, 33>>)
      card2 = Card.new("User Two", <<40, 41, 42, 43>>)
      
      Registry.enlist(card1)
      Registry.enlist(card2)
      
      # Get all users
      users = Registry.all()
      
      # Verify users are retrieved
      assert map_size(users) >= 2
      assert users[card1.pub_key].name == "User One"
      assert users[card2.pub_key].name == "User Two"
    end
  end

  describe "Registry.one/1" do
    test "retrieves a single user from Postgres" do
      # Create a user
      card = Card.new("Single User", <<50, 51, 52, 53>>)
      Registry.enlist(card)
      
      # Retrieve the user
      user = Registry.one(card.pub_key)
      
      # Verify correct user was retrieved
      assert user.name == "Single User"
      assert user.pub_key == <<50, 51, 52, 53>>
    end
    
    test "returns nil for non-existent user" do
      assert Registry.one(<<99, 99, 99, 99>>) == nil
    end
  end

  describe "Registry.remove/1" do
    test "removes user from Postgres" do
      # Create a user
      card = Card.new("To Be Removed", <<60, 61, 62, 63>>)
      pub_key = Registry.enlist(card)
      
      # Verify user exists before removal
      assert Repo.get(User, pub_key) != nil
      
      # Remove the user
      Registry.remove(pub_key)
      
      # Verify user no longer exists
      assert Repo.get(User, pub_key) == nil
    end
  end
end