defmodule Chat.Rooms.RequestRoomTest do
  use ExUnit.Case, async: true

  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils

  test "should create as usual" do
    {_alice, _identity, room} = "Alice" |> user_and_request_room()

    assert %Rooms.Room{type: :request} = room
  end

  test "should be seen in list" do
    {_alice, identity, _room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()

    {_, room_list} = Rooms.list([])

    assert nil != room_list |> Enum.find_value(&(&1.hash == room_hash))
  end

  test "requesting should work as for public" do
    {_alice, identity, room} = "Alice" |> user_and_request_room()
    room_hash = identity |> Utils.hash()
    bob = "Bob" |> User.login()

    Rooms.add_request(room_hash, bob)

    assert %Rooms.Room{requests: []} = Rooms.get(room_hash)
  end

  test "ahould be approved individually by any room key holder", do: :todo

  test "what else ?", do: :todo

  defp user_and_request_room(name) do
    alice = User.login(name)
    room_identity = Rooms.add(alice, "#{name}'s Request room", :request)
    room = Rooms.get(room_identity |> Utils.hash())

    {alice, room_identity, room}
  end
end
