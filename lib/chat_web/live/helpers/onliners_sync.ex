defmodule ChatWeb.Helpers.OnlinersSync do
  @moduledoc """
  Fetches user's keys from the LiveView socket and
  and sends them to the platform for the synchronization.
  """

  alias Chat.Identity
  alias Phoenix.LiveView.Socket
  alias Phoenix.PubSub

  @type socket :: Socket.t()

  @outgoing_topic "chat_onliners->platform_onliners"

  @spec get_user_keys(socket()) :: socket()
  def get_user_keys(%Socket{assigns: %{me: me, rooms: rooms}} = socket) do
    keys = Enum.map([me | rooms], &Identity.pub_key/1)
    PubSub.broadcast(Chat.PubSub, @outgoing_topic, {:user_keys, keys})

    socket
  end
end
