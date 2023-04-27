defmodule Chat.KeyShareTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.KeyShare
  alias Chat.Rooms
  alias Chat.User

  describe "key share" do
    setup do
      me = "Root" |> User.login()
      users = ["Kevin", "John", "Mike", "Liza"]
      user_cards = Enum.map(users, &User.login/1) |> Enum.map(&Card.from_identity/1)
      shares = KeyShare.generate_key_shares({me, user_cards})
      {:ok, me: me, users: users, user_cards: user_cards, shares: shares}
    end

    test "generate_key_shares/1", %{me: me, user_cards: user_cards} do
      key_shares = KeyShare.generate_key_shares({me, user_cards})
      assert Enum.count(key_shares) == Enum.count(user_cards)
      assert Enum.all?(key_shares, &Map.has_key?(&1, :key))
    end

    test "send_shares/2", %{me: me, shares: shares} do
      time_offset = 3
      assert shares |> KeyShare.send_shares({me, time_offset}) == :ok
    end
  end
end
