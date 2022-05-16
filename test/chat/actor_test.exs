defmodule Chat.ActorTest do
  use ExUnit.Case, async: true

  alias Chat.Actor
  alias Chat.Identity
  alias Chat.Rooms
  alias Chat.User

  test "should build json string on to_json" do
    me = User.login("Alice")

    room1 = Rooms.add(me, "1")
    room2 = Rooms.add(me, "2")

    me_actor = Actor.new(me, [room1, room2], %{})

    assert is_binary(me_actor |> Actor.to_json())
  end

  test "should restore from json" do
    me = User.login("Alice")

    room1 = %{priv_key: room1_key} = Rooms.add(me, "1")
    room2 = %{priv_key: room2_key} = Rooms.add(me, "2")

    me_actor = Actor.new(me, [room1, room2], %{})

    me_again = me_actor |> Actor.to_json() |> Actor.from_json()

    assert %{me: ^me, rooms: [%{priv_key: ^room1_key}, %{priv_key: ^room2_key}]} = me_again
  end

  test "encrypted with no password is same as to json" do
    me = User.login("Alice")

    room1 = Rooms.add(me, "1")
    room2 = Rooms.add(me, "2")

    me_actor = Actor.new(me, [room1, room2], %{})

    enc = me_actor |> Actor.to_encrypted_json("")

    assert enc == me_actor |> Actor.to_json()

    assert enc |> Actor.from_json() == enc |> Actor.from_encrypted_json("")
  end

  test "contact should recover as well" do
    me = User.login("Alice")
    contacts = %{(me |> Identity.pub_key()) => "Myself"}
    me_actor = Actor.new(me, [], contacts)

    me_again =
      me_actor
      |> Actor.to_json()
      |> Actor.from_json()

    assert me_again == me_actor
  end

  test "contacts should recover from encrypted" do
    me = User.login("Alice")
    contacts = %{(me |> Identity.pub_key()) => "Myself"}
    me_actor = Actor.new(me, [], contacts)

    me_again =
      me_actor
      |> Actor.to_encrypted_json("123")
      |> Actor.from_encrypted_json("123")

    assert me_again == me_actor
  end

  test "old_json should parse as well" do
    me = User.login("Alice")
    me_actor = Actor.new(me, [], %{})

    me_again =
      me_actor
      |> Actor.to_json()
      |> String.replace(",{}", "")
      |> Actor.from_json()

    assert me_again == me_actor
  end
end
