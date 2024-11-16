defmodule Chat.Broadcast do
  @moduledoc """
  Manage broadcasting to channels and pubsub
  """

  alias Chat.User.UsersBroker

  def new_user(card) do
    UsersBroker.put(card)
    Phoenix.PubSub.broadcast(Chat.PubSub, "chat::lobby", {:new_user, card})
    ChatWeb.Endpoint.broadcast("users:lobby", "new_user", card |> as_binary())
  end

  defp as_binary(term) do
    term
    |> Proxy.Serialize.serialize()
    |> then(&{:binary, &1})
  end
end
