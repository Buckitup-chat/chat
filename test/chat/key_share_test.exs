defmodule Chat.KeyShareTest do
  @moduledoc false
  use ChatWeb.DataCase, async: false

  alias Chat.Card
  alias Chat.KeyShare
  alias Chat.User

  describe "key share" do
    setup do
      me = "Root" |> User.login()
      pub_key = User.register(me)
      User.await_saved(pub_key)
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

    test "filter out broken skips the search when there are no spare shares", %{shares: shares} do
      decoded = shares |> Enum.map(&decoded_share/1)

      assert decoded == KeyShare.filter_out_broken(decoded)
    end

    test "filter out broken marks a duplicated share", %{shares: shares} do
      [first | _] = decoded = shares |> Enum.map(&decoded_share/1)
      copy = %{first | ref: "copy"}

      broken =
        (decoded ++ [copy]) |> KeyShare.filter_out_broken() |> Enum.filter(&KeyShare.broken?/1)

      assert [%{key: key}] = broken
      assert key == first.key
    end

    test "filter out broken tries pairs once single exclusions fail", %{shares: shares} do
      [first, second | _] = decoded = shares |> Enum.map(&decoded_share/1)
      copies = [%{first | ref: "copy1"}, %{second | ref: "copy2"}]

      broken =
        (decoded ++ copies) |> KeyShare.filter_out_broken() |> Enum.filter(&KeyShare.broken?/1)

      assert 2 == Enum.count(broken)
      assert broken |> Enum.map(& &1.key) |> Enum.sort() == Enum.sort([first.key, second.key])
    end

    test "user in share is broken for an unregistered user" do
      stranger = "Stranger" |> User.login()

      keystring = Base.encode64(stranger.private_key <> stranger.public_key)

      assert :user_keystring_broken == KeyShare.user_in_share(keystring)
    end
  end

  defp decoded_share(share) do
    [key, hash_sign] = share.key |> String.split("\n") |> Enum.map(&KeyShare.decode_content/1)

    %{key: key, hash: hash_sign, name: "#{UUID.uuid4()}.social_part", ref: UUID.uuid4()}
  end

  describe "content decoding" do
    test "decode content returns :error on invalid base64" do
      assert "ok" == KeyShare.decode_content(Base.encode64("ok"))
      assert :error == KeyShare.decode_content("not base64!")
    end

    test "user in share is broken for invalid base64" do
      assert :user_keystring_broken == KeyShare.user_in_share("not base64!")
    end

    test "read content decodes every line or fails as a whole" do
      dir = Path.join(System.tmp_dir!(), "key_share_#{UUID.uuid4()}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      good = Path.join(dir, "good.social_part")
      File.write!(good, Base.encode64("key") <> "\n" <> Base.encode64("hash"))
      bad = Path.join(dir, "bad.social_part")
      File.write!(bad, Base.encode64("key") <> "\n" <> "broken!")

      assert ["key", "hash"] == KeyShare.read_content(good)
      assert :error == KeyShare.read_content(bad)
    end
  end

  describe "composing and duplicates" do
    test "compose with no shares takes the uploaded ones" do
      assert MapSet.new([:a]) == KeyShare.compose([], [:a])
      assert MapSet.new([:a, :b]) == KeyShare.compose([:a], [:b, :a])
    end

    test "look for duplicates groups by key and excludes the lowest ref" do
      shares = [
        %{key: "k1", ref: "7"},
        %{key: "k1", ref: "3"},
        %{key: "k2", ref: "5"}
      ]

      assert [%{key: "k1", exclude: "3", ref: ["7", "3"]}] == KeyShare.look_for_duplicates(shares)
    end
  end

  describe "check" do
    test "passes four unique valid shares" do
      changeset = KeyShare.check(%{shares: valid_shares(4)})

      assert changeset.valid?
      assert :validate == changeset.action
    end

    test "requires the threshold amount" do
      changeset = KeyShare.check(%{shares: valid_shares(3)})

      refute changeset.valid?

      assert {_, [count: 4, validation: :length, kind: :min, type: :list]} =
               changeset.errors[:shares]
    end

    test "accepts an empty share list before threshold check" do
      changeset = KeyShare.check(%{shares: []})

      assert [shares: {_, [count: 4, validation: :length, kind: :min, type: :list]}] =
               changeset.errors
    end

    test "rejects shares of a different user file" do
      shares = valid_shares(4) |> List.update_at(0, &%{&1 | valid: false})

      changeset = KeyShare.check(%{shares: shares})

      assert {"mismatch: different user file", []} = changeset.errors[:shares]
    end

    test "rejects duplicated shares" do
      [first | rest] = valid_shares(4)
      shares = [first, %{first | ref: "9"} | rest]

      changeset = KeyShare.check(%{shares: shares})

      assert {"duplicates are found: " <> _, []} = changeset.errors[:shares]
    end

    test "changeset and schema describe shares" do
      assert %{shares: {:array, :map}} == KeyShare.schema()
      assert %Ecto.Changeset{changes: %{}} = KeyShare.changeset()
    end
  end

  defp valid_shares(amount) do
    1..amount |> Enum.map(&%{key: "key#{&1}", ref: "#{&1}", valid: true})
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
