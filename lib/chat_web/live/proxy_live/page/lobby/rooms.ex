defmodule ChatWeb.ProxyLive.Page.Lobby.Rooms do
  @moduledoc """
  Proxy lobby room list: fetching rooms from the proxied server, storing them in
  `ChatWeb.State.ServerRoomsState` and assigning the joined/new room lists.

  Used by `ChatWeb.ProxyLive.Page.Lobby` and `ChatWeb.ProxyLive.Page.Lobby.RoomRequests`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Tools.SocketPrivate

  alias ChatWeb.ProxyLive.Page.Lobby.RoomRequests
  alias ChatWeb.State.ServerRoomsState

  def assign_room_list(socket, search_term \\ "") do
    {joined, new} = ServerRoomsState.get_room_lists(socket, search_term)

    socket
    |> assign(:joined_rooms, joined)
    |> assign(:new_rooms, new)
  end

  def make_room_list_request(socket) do
    server = socket |> get_private(:server)
    pid = self()

    Task.start(fn ->
      rooms = Proxy.get_rooms(server)

      if is_list(rooms) do
        send(pid, {:lobby, {:room_list, rooms}})
      end
    end)
  end

  def populate_room_list(socket, room_list) do
    socket
    |> ServerRoomsState.set(room_list)
    |> assign_room_list()
    |> RoomRequests.join_approved_requests()
    |> assign_room_list()
  end
end
