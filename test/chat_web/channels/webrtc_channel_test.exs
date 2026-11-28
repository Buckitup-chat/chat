defmodule ChatWeb.WebRTCChannelTest do
  use ChatWeb.ChannelCase, async: true

  import Chat.Test.WebRTCChannelHelpers
  import ExUnit.CaptureLog

  alias ChatWeb.WebRTCChannel

  setup do
    room_id = unique_room_id()
    user_id = unique_user_id()
    socket = connect_to_room(room_id, user_id)
    :ok = Phoenix.PubSub.subscribe(Chat.PubSub, socket.topic)

    {:ok, socket: socket, room_id: room_id, user_id: user_id}
  end

  describe "join/3" do
    test "joins with valid room ID", %{socket: socket, room_id: room_id, user_id: user_id} do
      assert {:ok, _reply, joined} =
               subscribe_and_join(socket, WebRTCChannel, "room:#{room_id}", %{
                 "user_id" => user_id
               })

      assert joined.assigns.user_id == user_id
      assert joined.assigns.room_id == room_id

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_joined",
                       payload: %{user_id: ^user_id}
                     },
                     500,
                     "Expected user_joined message"

      leave(joined)
    end

    test "generates user ID if not provided", %{socket: socket, room_id: room_id} do
      assert {:ok, _reply, joined} =
               subscribe_and_join(socket, WebRTCChannel, "room:#{room_id}", %{})

      user_id = joined.assigns.user_id
      assert is_binary(user_id)
      assert String.starts_with?(user_id, "user_")

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_joined",
                       payload: %{user_id: ^user_id}
                     },
                     500,
                     "Expected user_joined message"

      leave(joined)
    end

    test "fails with invalid room ID" do
      socket = %Phoenix.Socket{handler: ChatWeb.WebRTCSocket, topic: "room:", assigns: %{}}

      assert {:error, %{reason: "invalid_room"}} = WebRTCChannel.join("room:", %{}, socket)
    end

    test "notifies other users when joining", %{
      socket: socket,
      room_id: room_id,
      user_id: user_id
    } do
      {:ok, _} = WebRTCChannel.join("room:" <> room_id, %{"user_id" => user_id}, socket)

      user2_id = unique_user_id("user2")
      room_id |> connect_to_room(user2_id) |> join_room()

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_joined",
                       payload: %{user_id: ^user2_id}
                     },
                     200,
                     "Expected user_joined message for second user"
    end
  end

  describe "handle_in/3" do
    test "handles signal message", %{socket: socket, user_id: user_id} do
      socket = join_room(socket)

      push(socket, "signal", %{
        "to" => "other_user",
        "data" => %{"test" => true},
        "type" => "test"
      })

      assert_broadcast "signal", %{
        from: ^user_id,
        to: "other_user",
        data: %{"test" => true},
        type: "test"
      }
    end

    test "does not broadcast signal message to self", %{socket: socket, user_id: user_id} do
      socket = join_room(socket)
      push(socket, "signal", %{"to" => user_id, "data" => %{"test" => true}, "type" => "test"})

      refute_broadcast "signal", %{"to" => ^user_id}
    end

    test "ignores signal with missing fields", %{socket: socket} do
      logs =
        capture_log(fn ->
          ref = socket |> join_room() |> push("signal", %{})

          refute_reply ref, :error, %{reason: _}
          refute_reply ref, :ok, %{}
        end)

      assert logs =~ "Received invalid signal message"
    end

    test "handles ice_candidate message", %{socket: socket, user_id: user_id} do
      candidate = %{"candidate" => "candidate:1", "sdpMid" => "0", "sdpMLineIndex" => 0}

      socket = join_room(socket)
      push(socket, "ice_candidate", %{"to" => "other_user", "candidate" => candidate})

      assert_broadcast "ice_candidate", %{from: ^user_id, to: "other_user", candidate: ^candidate}
    end

    test "handles sdp message", %{socket: socket, user_id: user_id} do
      sdp = %{"type" => "offer", "sdp" => "v=0\r\no=..."}

      socket = join_room(socket)
      push(socket, "sdp", %{"to" => "other_user", "type" => "offer", "sdp" => sdp})

      assert_broadcast "sdp", %{from: ^user_id, to: "other_user", type: "offer", sdp: ^sdp}
    end
  end

  describe "terminate/2" do
    test "broadcasts user_left message when terminating", %{socket: socket, user_id: user_id} do
      :ok = socket |> join_room() |> then(&WebRTCChannel.terminate(:shutdown, &1))

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_left",
                       payload: %{user_id: ^user_id, reason: :shutdown}
                     },
                     1000,
                     "Expected user_left message"
    end

    test "handles termination with different reasons", %{socket: socket, user_id: user_id} do
      reason = :network_issue
      :ok = socket |> join_room() |> then(&WebRTCChannel.terminate(reason, &1))

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_left",
                       payload: %{user_id: ^user_id, reason: ^reason}
                     },
                     1000,
                     "Expected user_left message with custom reason"
    end

    test "handles termination without room_id in assigns" do
      socket = %Phoenix.Socket{
        handler: ChatWeb.WebRTCSocket,
        topic: "room:test_room",
        assigns: %{user_id: "test_user"}
      }

      assert :ok = WebRTCChannel.terminate(:shutdown, socket)
    end
  end
end
