defmodule Chat.UtilsTest do
  use ExUnit.Case, async: true

  alias Chat.Actor
  alias Chat.Identity
  alias Chat.Utils

  test "blob crypt" do
    data = "1234"
    type = "text/plain"

    {encrypted, secret} = Utils.encrypt_blob({data, type})

    assert encrypted != {data, type}

    assert {^data, ^type} = Utils.decrypt_blob(encrypted, secret)
  end

  test "pagination" do
    list = [
      %{timestamp: 100},
      %{timestamp: 19},
      %{timestamp: 18},
      %{timestamp: 18},
      %{timestamp: 15},
      %{timestamp: 11}
    ]

    assert [
             %{timestamp: 18},
             %{timestamp: 18}
           ] = Utils.page(list, 19, 2)
  end

  test "test binhash" do
    bin = :binary.copy(<<255>>, 32)

    assert "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" == Utils.hash(bin)
  end

  test "" do
    me = Identity.create("Alice")
    card = Chat.Card.from_identity(me)

    assert Utils.hash(me) == Utils.hash(card)
  end

  test "Actor encoding should work fine" do
    [me, room1, room2] =
      ["Alice", "room 1", "room 2"]
      |> Enum.map(&Identity.create/1)

    actor = Actor.new(me, [room1, room2], %{})
    password = "123456543211"

    encrypted =
      actor
      |> Actor.to_encrypted_json(password)

    assert is_binary(encrypted)

    decrypted = encrypted |> Actor.from_encrypted_json(password)

    assert decrypted.me == actor.me

    assert decrypted.rooms |> Enum.map(& &1.priv_key) == actor.rooms |> Enum.map(& &1.priv_key)
  end

  test "Identity encrypt should work" do
    me = Identity.create("me")

    text = "hello world"

    encrypted = text |> Utils.encrypt(me)

    assert encrypted != text

    assert ^text = Utils.decrypt(encrypted, me)
  end
end
