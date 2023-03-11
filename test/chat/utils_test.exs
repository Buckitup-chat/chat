defmodule Chat.UtilsTest do
  use ExUnit.Case, async: true

  alias Chat.Actor
  alias Chat.Identity
  alias Chat.Utils

  test "blob crypt" do
    data = "1234"
    type = "text/plain"
    secret = Enigma.generate_secret()

    encrypted = Enigma.cipher([data, type], secret)

    assert encrypted != {data, type}

    assert [^data, ^type] = Enigma.decipher(encrypted, secret)
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

  test "" do
    me = Identity.create("Alice")
    card = Chat.Card.from_identity(me)

    assert Enigma.hash(me) == Enigma.hash(card)
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

    assert decrypted.rooms |> Enum.map(& &1.private_key) ==
             actor.rooms |> Enum.map(& &1.private_key)
  end
end
