defmodule ChatWeb.MainLive.Page.Login do
  @moduledoc "Login part of chat"
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.AdminRoom
  alias Chat.Identity
  alias Chat.Log
  alias Chat.User
  alias ChatWeb.MainLive.Page

  @local_store_key "buckitUp-chat-auth-v2"

  def create_user(socket, name) do
    me = User.login(name |> String.trim())
    id = User.register(me)
    # todo: check setting time before creating
    Log.sign_in(me, socket.assigns.monotonic_offset |> Chat.Time.monotonic_to_unix())

    socket
    |> assign_logged_user(me, id)
    |> store()
    |> close()
    |> Page.Lobby.notify_new_user(me |> Chat.Card.from_identity())
  end

  def load_user(socket, data) do
    {me, rooms} = User.device_decode(data)

    socket
    |> load_user(me, rooms)
  end

  def load_user(socket, %Identity{} = me, rooms) do
    id =
      me
      |> User.login()
      |> User.register()

    Log.visit(me, socket.assigns.monotonic_offset |> Chat.Time.monotonic_to_unix())

    socket
    |> assign_logged_user(me, id, rooms)
    |> close()
    |> Page.Lobby.notify_new_user(me |> Chat.Card.from_identity())
  end

  def store_new_room(%{assigns: %{rooms: rooms, room_map: room_map}} = socket, new_room_identity) do
    socket
    |> assign(:rooms, [new_room_identity | rooms])
    |> assign(
      :room_map,
      Map.put(room_map, new_room_identity |> Identity.pub_key(), new_room_identity)
    )
    |> store()
  end

  def store(%{assigns: %{rooms: rooms, me: me}} = socket) do
    socket
    |> push_event("store", %{
      key: @local_store_key,
      data: User.device_encode(me, rooms)
    })
  end

  def clear(%{assigns: %{rooms: _rooms, me: _me}} = socket) do
    socket
    |> push_event("clear", %{key: @local_store_key})
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
    |> assign(
      :room_map,
      rooms |> Enum.map(fn room -> {room |> Identity.pub_key(), room} end) |> Map.new()
    )
    |> maybe_create_admin_room()
  end

  def close(socket) do
    socket
    |> assign(:need_login, false)
  end

  defp maybe_create_admin_room(socket) do
    if AdminRoom.created?() do
      socket
    else
      socket
      |> store_new_room(AdminRoom.create())
    end
  end
end
