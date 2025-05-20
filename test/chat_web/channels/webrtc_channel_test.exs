defmodule ChatWeb.WebRTCChannelTest do
  use ChatWeb.ChannelCase, async: true
  alias ChatWeb.WebRTCChannel
  import ExUnit.CaptureLog

  setup do
    # Use the application's PubSub server
    pubsub_server = Chat.PubSub

    # Create a test room ID and user ID
    room_id = "test_room_#{System.unique_integer([:positive])}"
    user_id = "user_#{System.unique_integer([:positive])}"

    # Create a socket using the WebRTCSocket
    {:ok, socket} = Phoenix.ChannelTest.connect(ChatWeb.WebRTCSocket, %{"user_id" => user_id})

    # Add the topic to the socket
    socket = %{socket | topic: "room:#{room_id}"}

    # Subscribe the test process to the room topic
    :ok = Phoenix.PubSub.subscribe(pubsub_server, socket.topic)

    {:ok, socket: socket, room_id: room_id, user_id: user_id, pubsub_server: pubsub_server}
  end

  defp push_message(socket, event, payload) do
    # Subscribe to the channel if not already joined
    socket =
      if socket.channel_pid do
        socket
      else
        {:ok, _, socket} =
          subscribe_and_join(socket, WebRTCChannel, socket.topic, %{
            "user_id" => socket.assigns.user_id
          })

        socket
      end

    # Push the message
    push(socket, event, payload)
    # Return the updated socket
    socket
  end

  describe "join/3" do
    test "joins with valid room ID", %{socket: socket, room_id: room_id, user_id: user_id} do
      params = %{"user_id" => user_id}

      # Subscribe to the topic before joining
      :ok = Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room_id}")

      # Join the channel
      assert {:ok, _reply, updated_socket} =
               subscribe_and_join(socket, WebRTCChannel, "room:#{room_id}", params)

      # Verify the socket assigns were updated
      assert updated_socket.assigns.user_id == user_id
      assert updated_socket.assigns.room_id == room_id

      # Wait for the join notification with retries
      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_joined",
                       payload: %{user_id: ^user_id}
                     },
                     500,
                     "Expected user_joined message"

      # Clean up
      leave(updated_socket)
    end

    test "generates user ID if not provided", %{socket: socket, room_id: room_id} do
      # Subscribe to the topic before joining
      :ok = Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room_id}")

      # Join without providing a user_id
      assert {:ok, _reply, updated_socket} =
               subscribe_and_join(socket, WebRTCChannel, "room:#{room_id}", %{})

      # Verify a user_id was generated
      assert is_binary(updated_socket.assigns.user_id)
      assert String.starts_with?(updated_socket.assigns.user_id, "user_")

      # Wait for the join notification with retries
      user_id = updated_socket.assigns.user_id

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_joined",
                       payload: %{user_id: ^user_id}
                     },
                     500,
                     "Expected user_joined message"

      # Clean up
      leave(updated_socket)
    end

    test "fails with invalid room ID" do
      socket = %Phoenix.Socket{
        handler: ChatWeb.WebRTCSocket,
        topic: "room:",
        assigns: %{}
      }

      assert {:error, %{reason: "invalid_room"}} = WebRTCChannel.join("room:", %{}, socket)
    end

    test "notifies other users when joining", %{
      socket: socket,
      room_id: room_id,
      user_id: user_id
    } do
      # First user joins
      {:ok, _} = WebRTCChannel.join("room:" <> room_id, %{"user_id" => user_id}, socket)

      # Second user joins
      user2_id = "user2_#{System.unique_integer([:positive])}"
      {:ok, socket2} = Phoenix.ChannelTest.connect(ChatWeb.WebRTCSocket, %{"user_id" => user2_id})
      socket2 = %{socket2 | topic: "room:#{room_id}"}

      # Join the second user
      {:ok, _, _} =
        subscribe_and_join(socket2, WebRTCChannel, socket2.topic, %{"user_id" => user2_id})

      # First user should receive a notification about the second user
      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_joined",
                       payload: %{user_id: ^user2_id}
                     },
                     200,
                     "Expected user_joined message for second user"
    end
  end

  describe "handle_in/3" do
    test "handles signal message", %{socket: socket} do
      # Push a signal message
      socket =
        push_message(socket, "signal", %{
          "to" => "other_user",
          "data" => %{"test" => true},
          "type" => "test"
        })

      # Verify the message was broadcast
      user_id = socket.assigns.user_id

      assert_broadcast "signal", %{
        from: ^user_id,
        to: "other_user",
        data: %{"test" => true},
        type: "test"
      }
    end

    test "does not broadcast signal message to self", %{socket: socket, user_id: user_id} do
      # Join the channel
      {:ok, _, socket} =
        subscribe_and_join(socket, WebRTCChannel, socket.topic, %{"user_id" => user_id})

      # Push a signal message to self (should not be delivered)
      push(socket, "signal", %{"to" => user_id, "data" => %{"test" => true}, "type" => "test"})

      # Verify no message was broadcast (since it's to self)
      refute_broadcast "signal", %{"to" => ^user_id}
    end

    test "ignores signal with missing fields", %{socket: socket} do
      # Capture logs for verification
      logs =
        capture_log(fn ->
          # Join the channel
          {:ok, _, socket} =
            subscribe_and_join(socket, WebRTCChannel, socket.topic, %{
              "user_id" => socket.assigns.user_id
            })

          # Push a signal message with missing required fields
          ref = push(socket, "signal", %{})

          # The channel should not crash and should not reply
          refute_reply ref, :error, %{reason: _}
          refute_reply ref, :ok, %{}
        end)

      # Verify that the invalid message was logged
      assert logs =~ "Received invalid signal message"
    end

    test "handles ice_candidate message", %{socket: socket, pubsub_server: pubsub_server} do
      # Subscribe to the room topic to receive broadcast messages
      :ok = Phoenix.PubSub.subscribe(pubsub_server, socket.topic)

      # Push an ICE candidate message
      candidate = %{"candidate" => "candidate:1", "sdpMid" => "0", "sdpMLineIndex" => 0}

      socket =
        push_message(socket, "ice_candidate", %{"to" => "other_user", "candidate" => candidate})

      # Verify the message was broadcast
      user_id = socket.assigns.user_id

      assert_broadcast "ice_candidate", %{
        from: ^user_id,
        to: "other_user",
        candidate: ^candidate
      }
    end

    test "handles sdp message", %{socket: socket, pubsub_server: pubsub_server} do
      # Subscribe to the room topic to receive broadcast messages
      :ok = Phoenix.PubSub.subscribe(pubsub_server, socket.topic)

      # Push an SDP message
      sdp = %{"type" => "offer", "sdp" => "v=0\r\no=..."}

      socket =
        push_message(socket, "sdp", %{"to" => "other_user", "type" => "offer", "sdp" => sdp})

      # Verify the message was broadcast
      user_id = socket.assigns.user_id

      assert_broadcast "sdp", %{
        from: ^user_id,
        to: "other_user",
        type: "offer",
        sdp: ^sdp
      }
    end
  end

  describe "terminate/2" do
    test "broadcasts user_left message when terminating", %{socket: socket, user_id: user_id} do
      # Subscribe to the room topic
      :ok = Phoenix.PubSub.subscribe(Chat.PubSub, socket.topic)

      # Join the channel
      {:ok, _, socket} =
        subscribe_and_join(socket, WebRTCChannel, socket.topic, %{"user_id" => user_id})

      # Terminate the channel
      :ok = WebRTCChannel.terminate(:shutdown, socket)

      # Verify user_left message was broadcast
      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_left",
                       payload: %{
                         user_id: ^user_id,
                         reason: :shutdown
                       }
                     },
                     1000,
                     "Expected user_left message"
    end

    test "handles termination with different reasons", %{socket: socket, user_id: user_id} do
      # Subscribe to the room topic
      :ok = Phoenix.PubSub.subscribe(Chat.PubSub, socket.topic)

      # Join the channel
      {:ok, _, socket} =
        subscribe_and_join(socket, WebRTCChannel, socket.topic, %{"user_id" => user_id})

      # Terminate with a custom reason
      reason = :network_issue
      :ok = WebRTCChannel.terminate(reason, socket)

      # Verify user_left message was broadcast with the custom reason
      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_left",
                       payload: %{
                         user_id: ^user_id,
                         reason: ^reason
                       }
                     },
                     1000,
                     "Expected user_left message with custom reason"
    end

    test "handles termination without room_id in assigns" do
      # Create a socket without room_id in assigns
      socket = %Phoenix.Socket{
        handler: ChatWeb.WebRTCSocket,
        topic: "room:test_room",
        assigns: %{user_id: "test_user"}
      }

      # This should not raise an error
      assert :ok = WebRTCChannel.terminate(:shutdown, socket)
    end
  end

  describe "integration test" do
    test "multiple users can join and exchange messages" do
      # Create test users and room
      room_id = "test_room_#{System.unique_integer([:positive])}"
      user1_id = "user1_#{System.unique_integer([:positive])}"
      user2_id = "user2_#{System.unique_integer([:positive])}"

      # Create and connect first user
      {:ok, socket1} = Phoenix.ChannelTest.connect(ChatWeb.WebRTCSocket, %{"user_id" => user1_id})
      socket1 = %{socket1 | topic: "room:#{room_id}"}

      # Create and connect second user
      {:ok, socket2} = Phoenix.ChannelTest.connect(ChatWeb.WebRTCSocket, %{"user_id" => user2_id})
      socket2 = %{socket2 | topic: "room:#{room_id}"}

      # Subscribe test process to the room topic
      :ok = Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room_id}")

      # First user joins
      {:ok, _, socket1} =
        subscribe_and_join(socket1, WebRTCChannel, "room:#{room_id}", %{"user_id" => user1_id})

      # Wait for first user join notification
      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_joined",
                       payload: %{user_id: ^user1_id}
                     },
                     1000,
                     "Expected user_joined for first user"

      # Second user joins - use _ prefix to indicate unused variable
      {:ok, _, _socket2} =
        subscribe_and_join(socket2, WebRTCChannel, "room:#{room_id}", %{"user_id" => user2_id})

      # Wait for second user join notification
      assert_receive %Phoenix.Socket.Broadcast{
                       event: "user_joined",
                       payload: %{user_id: ^user2_id}
                     },
                     1000,
                     "Expected user_joined for second user"

      # User1 sends a message to User2
      message = %{"text" => "Hello, User2!"}

      _ref =
        push(socket1, "signal", %{
          "to" => user2_id,
          "data" => message,
          "type" => "chat"
        })

      # User2 should receive the message
      assert_receive %Phoenix.Socket.Broadcast{
                       event: "signal",
                       payload: %{
                         from: ^user1_id,
                         to: ^user2_id,
                         data: ^message,
                         type: "chat"
                       }
                     },
                     1000,
                     "Expected message from User1 to User2"

      # User1 sends ICE candidates to User2
      candidate1 = %{"candidate" => "candidate1", "sdpMid" => "0", "sdpMLineIndex" => 0}
      push(socket1, "ice_candidate", %{"to" => user2_id, "candidate" => candidate1})

      # Verify User2 received the ICE candidate
      assert_receive %Phoenix.Socket.Broadcast{
                       event: "ice_candidate",
                       payload: %{
                         from: ^user1_id,
                         to: ^user2_id,
                         candidate: ^candidate1
                       }
                     },
                     1000,
                     "Expected ICE candidate"
    end

    test "handles concurrent users and messages" do
      room_id = "test_room_#{System.unique_integer([:positive])}"
      num_users = 5

      # Create and connect users
      users =
        for i <- 1..num_users do
          user_id = "user_#{i}_#{System.unique_integer([:positive])}"

          {:ok, socket} =
            Phoenix.ChannelTest.connect(ChatWeb.WebRTCSocket, %{"user_id" => user_id})

          socket = %{socket | topic: "room:#{room_id}"}
          {user_id, socket}
        end

      # Subscribe test process to the room
      Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room_id}")

      # Join all users
      users =
        Enum.map(users, fn {user_id, socket} ->
          {:ok, _, socket} =
            subscribe_and_join(socket, WebRTCChannel, socket.topic, %{"user_id" => user_id})

          {user_id, socket}
        end)

      # Wait for all join notifications
      :timer.sleep(100)

      # Each user sends a message to all other users
      for {from_id, from_socket} <- users do
        for {to_id, _} <- users, to_id != from_id do
          message = %{"text" => "Hello from #{from_id} to #{to_id}"}

          push(from_socket, "signal", %{
            "to" => to_id,
            "data" => message,
            "type" => "chat"
          })

          # Verify the message was received
          assert_receive %Phoenix.Socket.Broadcast{
                           event: "signal",
                           payload: %{
                             from: ^from_id,
                             to: ^to_id,
                             data: ^message,
                             type: "chat"
                           }
                         },
                         100,
                         "Expected message from #{from_id} to #{to_id}"
        end
      end
    end
  end
end
