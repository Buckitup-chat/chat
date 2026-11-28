defmodule ChatWeb.WebRTCChannelIntegrationTest do
  use ChatWeb.ChannelCase, async: true

  import Chat.Test.WebRTCChannelHelpers

  test "multiple users can join and exchange messages" do
    room_id = unique_room_id()
    user1_id = unique_user_id("user1")
    user2_id = unique_user_id("user2")
    socket1 = connect_to_room(room_id, user1_id)
    socket2 = connect_to_room(room_id, user2_id)
    :ok = Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room_id}")

    socket1 = join_room(socket1)

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "user_joined",
                     payload: %{user_id: ^user1_id}
                   },
                   1000,
                   "Expected user_joined for first user"

    join_room(socket2)

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "user_joined",
                     payload: %{user_id: ^user2_id}
                   },
                   1000,
                   "Expected user_joined for second user"

    message = %{"text" => "Hello, User2!"}
    push(socket1, "signal", %{"to" => user2_id, "data" => message, "type" => "chat"})

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "signal",
                     payload: %{from: ^user1_id, to: ^user2_id, data: ^message, type: "chat"}
                   },
                   1000,
                   "Expected message from User1 to User2"

    candidate = %{"candidate" => "candidate1", "sdpMid" => "0", "sdpMLineIndex" => 0}
    push(socket1, "ice_candidate", %{"to" => user2_id, "candidate" => candidate})

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "ice_candidate",
                     payload: %{from: ^user1_id, to: ^user2_id, candidate: ^candidate}
                   },
                   1000,
                   "Expected ICE candidate"
  end

  test "handles concurrent users and messages" do
    room_id = unique_room_id()
    users = joined_users(room_id, 5)

    for {from_id, from_socket} <- users, {to_id, _} <- users, to_id != from_id do
      message = %{"text" => "Hello from #{from_id} to #{to_id}"}
      push(from_socket, "signal", %{"to" => to_id, "data" => message, "type" => "chat"})

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "signal",
                       payload: %{from: ^from_id, to: ^to_id, data: ^message, type: "chat"}
                     },
                     1000,
                     "Expected message from #{from_id} to #{to_id}"
    end
  end

  defp joined_users(room_id, count) do
    users =
      for i <- 1..count do
        user_id = unique_user_id("user_#{i}")
        {user_id, connect_to_room(room_id, user_id)}
      end

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room_id}")

    Enum.map(users, fn {user_id, socket} -> {user_id, join_room(socket)} end)
  end
end
