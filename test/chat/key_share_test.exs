defmodule Chat.KeyShareTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.KeyShare
  alias Chat.User

  describe "key share" do
    setup do
      me = "Root" |> User.login()
      User.register(me)
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

    test "save_shares/2", %{me: me, shares: shares} do
      time_offset = 3
      saved_shares = shares |> KeyShare.save_shares({me, time_offset})
      assert Enum.count(saved_shares) == Enum.count(shares)
      assert Enum.all?(saved_shares, &Map.has_key?(&1, :entry))
    end

    test "user in share", %{shares: shares} do
      keystring =
        shares
        |> Enum.map(&(Map.get(&1, :key) |> String.split("\n") |> Enum.at(0)))
        |> Enum.map(&KeyShare.decode_content/1)
        |> Enigma.recover_secret_from_shares()

      assert {:ok, %Card{} = _user} = KeyShare.user_in_share(keystring)
    end

    test "filter out broken", %{shares: shares} do
      shares =
        shares
        |> Enum.map(fn share ->
          [key, hash_sign] =
            share.key |> String.split("\n") |> Enum.map(&KeyShare.decode_content/1)

          %{
            key: key,
            hash: hash_sign,
            name: "#{UUID.uuid4()}.social_part",
            ref: :rand.uniform(1000) |> Integer.to_string()
          }
        end)
        |> Kernel.++(broken_share())

      broken_marked = shares |> KeyShare.filter_out_broken()

      assert broken_marked |> Enum.any?(&KeyShare.broken?(&1)) == true
    end
  end

  defp broken_share do
    [
      %{
        key:
          "dfXR6t95ZLTXbZlfmnKnd7zwLx+6cPSwlvfgHb4YmCjbPmjLhW5T6gXM6Y3s+jpKc93NoBELxWpSunZeEfyXf8AqPktoJSy+owi9wbA7KWT4vakrpCtD/7c="
          |> Base.decode64()
          |> elem(1),
        hash:
          "MEQCICL6e+eHMyPIpb8V6ySORSaBYhadEOePSdCMdiaqv3D5AiAfFXp9eBQTaxv+JL6RGAZWC9FdKC1eyBWnJjEnEqRaGw=="
          |> Base.decode64()
          |> elem(1),
        name: "#{UUID.uuid4()}.social_part",
        ref: :rand.uniform(1000) |> Integer.to_string()
      }
    ]
  end
end
