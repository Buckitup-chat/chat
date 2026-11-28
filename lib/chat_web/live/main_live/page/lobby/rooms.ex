defmodule ChatWeb.MainLive.Page.Lobby.Rooms do
  @moduledoc """
  The lobby room list: creating a room, the joined/new room lists (optionally
  filtered by a search term), and whether I hold the admin room key.

  Part of the `ChatWeb.MainLive.Page.Lobby` namespace.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Chat.AdminRoom
  alias Chat.Db.ChangeTracker
  alias Chat.Log
  alias Chat.Rooms
  alias Chat.Rooms.RoomsBroker
  alias ChatWeb.MainLive.Page
  alias Phoenix.PubSub

  def new_room(%{assigns: %{me: me, monotonic_offset: time_offset}} = socket, name, type)
      when type in [:public, :request, :private, :cargo] do
    {cargo?, type} =
      case type do
        :cargo ->
          {true, :request}

        type ->
          {false, type}
      end

    {new_room_identity, new_room} =
      Rooms.add(me, name, type) |> tap(fn {_, room} -> RoomsBroker.put(room) end)

    new_room_card = Chat.Card.from_identity(new_room_identity)
    send(self(), {:maybe_activate_cargo_room, cargo?, new_room, new_room_identity})

    me |> Log.create_room(Chat.Time.monotonic_to_unix(time_offset), new_room_identity, type)

    ChangeTracker.on_saved(fn ->
      PubSub.broadcast!(Chat.PubSub, Page.Lobby.topic(), {:new_room, new_room_card})
    end)

    socket
    |> Page.Room.close()
    |> Page.Room.store_new(new_room_identity)
    |> Page.Shared.update_onliners_presence()
    |> Page.Room.init({new_room_identity, new_room})
  end

  def assign_room_list(%{assigns: %{room_map: rooms, my_id: my_id}} = socket, search_term \\ "") do
    {joined, new} =
      if search_term == "",
        do: RoomsBroker.list(rooms),
        else: RoomsBroker.list(rooms, search_term)

    new =
      Enum.map(new, fn room ->
        Map.put(room, :is_requested?, Rooms.requested_by?(room.pub_key, my_id))
      end)

    socket
    |> assign(:joined_rooms, joined)
    |> assign(:new_rooms, new)
  end

  def assign_admin(%{assigns: %{room_map: rooms}} = socket) do
    has_admin_key =
      with admin_pub_key <- AdminRoom.pub_key(),
           false <- is_nil(admin_pub_key),
           some_data <- admin_pub_key |> Enigma.hash(),
           identity <- rooms[admin_pub_key],
           false <- is_nil(identity),
           sign <- Enigma.sign(some_data, identity.private_key),
           true <- Enigma.valid_sign?(sign, some_data, admin_pub_key) do
        true
      else
        _ -> false
      end

    socket |> assign(:is_admin, has_admin_key)
  end
end
