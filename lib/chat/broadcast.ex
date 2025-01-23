defmodule Chat.Broadcast do
  @moduledoc """
  Manage broadcasting to channels and pubsub

  local broadcast is for LiveViews
  remote broadcast is for WebSocket clients
  """

  alias Chat.User.UsersBroker

  def new_user(card) do
    # todo: move UsersBroker usage out
    UsersBroker.put(card)

    local_broadcast("chat::lobby", {:new_user, card})
    remote_broadcast("new_user", card)
  end

  def room_requested(room, requester_pub_key) do
    local_broadcast("chat::lobby", {:room_request, room, requester_pub_key})
    remote_broadcast("room_request", {room, requester_pub_key})
  end

  def new_dialog_message(indexed_message, dialog_key) do
    dialog_topic = "dialog:" <> dialog_key
    local_broadcast(dialog_topic, {:dialog, {:new_dialog_message, indexed_message}})

    remote_broadcast("new_dialog_message", {dialog_key, indexed_message})
  end

  ### Utilities

  defp local_broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Chat.PubSub, topic, message)
  end

  defp remote_broadcast(topic, message) do
    ChatWeb.Endpoint.broadcast("proxy:clients", topic, message |> as_binary())
  end

  defp as_binary(term) do
    term
    |> Proxy.Serialize.serialize()
    |> then(&{:binary, &1})
  end
end
