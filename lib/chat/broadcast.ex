defmodule Chat.Broadcast do
  @moduledoc """
  Manage broadcasting to channels and pubsub
  """

  alias Chat.User.UsersBroker

  def new_user(card) do
    UsersBroker.put(card)
    Phoenix.PubSub.broadcast(Chat.PubSub, "chat::lobby", {:new_user, card})
    ChatWeb.Endpoint.broadcast("proxy:clients", "new_user", card |> as_binary())
  end

  def new_dialog_message(indexed_message, dialog_key) do
    dialog_topic = "dialog:" <> dialog_key

    Phoenix.PubSub.broadcast(
      Chat.PubSub,
      dialog_topic,
      {:dialog, {:new_dialog_message, indexed_message}}
    )

    ChatWeb.Endpoint.broadcast(
      "proxy:clients",
      "new_dialog_message",
      {dialog_key, indexed_message} |> as_binary()
    )
  end

  defp as_binary(term) do
    term
    |> Proxy.Serialize.serialize()
    |> then(&{:binary, &1})
  end
end
