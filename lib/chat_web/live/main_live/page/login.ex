defmodule ChatWeb.MainLive.Page.Login do
  @moduledoc "Login part of chat"
  import Phoenix.LiveView, only: [assign: 3, push_event: 3]

  alias Chat.User
  alias ChatWeb.MainLive.Page

  @local_store_key "buckitUp-chat-auth"

  def create_user(socket, name) do
    me = User.login(name |> String.trim())
    id = User.register(me)

    socket
    |> assign_logged_user(me, id)
    |> store()
    |> Page.Lobby.notify_new_user(me |> Chat.Card.from_identity())
  end

  def load_user(socket, data) do
    {me, rooms} = User.device_decode(data)
    id = User.register(me)

    socket
    |> assign_logged_user(me, id, rooms)
    |> Page.Lobby.notify_new_user(me |> Chat.Card.from_identity())
  end

  def store(%{assigns: %{rooms: rooms, me: me}} = socket) do
    socket
    |> push_event("store", %{
      key: @local_store_key,
      data: User.device_encode(me, rooms)
    })
  end

  def check_stored(socket) do
    socket
    |> push_event("restore", %{key: @local_store_key, event: "restoreAuth"})
  end

  defp assign_logged_user(socket, me, id, rooms \\ []) do
    socket
    |> assign(:me, me)
    |> assign(:my_id, id)
    |> assign(:rooms, rooms)
    |> assign(:need_login, false)
  end
end
