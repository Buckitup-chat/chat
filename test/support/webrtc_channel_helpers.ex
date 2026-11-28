defmodule Chat.Test.WebRTCChannelHelpers do
  @moduledoc "Connect and join helpers for `ChatWeb.WebRTCChannel` tests."

  import Phoenix.ChannelTest

  alias ChatWeb.WebRTCChannel

  @endpoint ChatWeb.Endpoint

  @doc "Unique room id, so async tests never share a PubSub topic."
  def unique_room_id, do: "test_room_#{System.unique_integer([:positive])}"

  @doc "Unique user id with the given prefix."
  def unique_user_id(prefix \\ "user"), do: "#{prefix}_#{System.unique_integer([:positive])}"

  @doc "Connects `user_id` over `ChatWeb.WebRTCSocket`, with the socket topic set to the room."
  def connect_to_room(room_id, user_id) do
    {:ok, socket} = connect(ChatWeb.WebRTCSocket, %{"user_id" => user_id})
    %{socket | topic: "room:#{room_id}"}
  end

  @doc "Joins the socket's room as its own `user_id`; returns the joined socket."
  def join_room(socket) do
    {:ok, _, socket} =
      subscribe_and_join(socket, WebRTCChannel, socket.topic, %{
        "user_id" => socket.assigns.user_id
      })

    socket
  end
end
