defmodule Chat.Broadcast do
  @moduledoc """
  Manage broadcasting to channels and pubsub

  local broadcast is for LiveViews
  remote broadcast is for WebSocket clients
  remote channels are prefixed with "remote::" and has different message format
  """
  require Logger

  alias Chat.Broadcast.Topic
  alias Chat.User.UsersBroker

  def new_user(card) do
    # todo: move UsersBroker usage out
    UsersBroker.put(card)

    Topic.lobby()
    |> local_broadcast({:new_user, card})
    |> remote_broadcast("new_user", card)
  end

  def new_room(room_card) do
    Topic.lobby()
    |> local_broadcast({:new_room, room_card})
    |> remote_broadcast("new_room", room_card)
  end

  def room_requested(room, requester_pub_key) do
    Topic.lobby()
    |> local_broadcast({:room_request, room, requester_pub_key})
    |> remote_broadcast("room_request", {room, requester_pub_key})
  end

  def room_request_approved(user_key, room_key, ciphered) do
    Topic.user_room_approval(user_key)
    |> local_broadcast({:room_request_approved, ciphered, user_key, room_key})
    |> remote_broadcast("room_request_approved", {room_key, ciphered})
  end

  def new_dialog_message(indexed_message, dialog_key) do
    Topic.dialog(dialog_key)
    |> local_broadcast({:dialog, {:new_dialog_message, indexed_message}})
    |> remote_broadcast("new_dialog_message", indexed_message)
  end

  ### Utilities

  defp local_broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Chat.PubSub, topic, message)
    # ["local", topic, message] |> dbg()
    log([topic], message)
    topic
  end

  defp remote_broadcast(topic, event, message) do
    ChatWeb.Endpoint.broadcast("remote::" <> topic, event, message |> as_binary())
    # ["remote::" <> topic, event, message] |> dbg()
    log(["remote::" <> topic, event], message)
    topic
  end

  defp as_binary(term) do
    term
    |> Proxy.Serialize.serialize()
    |> then(&{:binary, &1})
  end

  defp log(crumbs, message) do
    topics = Enum.map_join(crumbs, " ", &"[#{&1}]")

    ["[broadcast] ", topics, "  ", message |> inspect()] |> Logger.info()
  end
end
