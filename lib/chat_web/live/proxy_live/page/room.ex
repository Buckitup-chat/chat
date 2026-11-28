defmodule ChatWeb.ProxyLive.Page.Room do
  @moduledoc "Room page"

  use ChatWeb, :component

  import Phoenix.Component, only: [assign: 3]

  alias ChatWeb.MainLive.Page.Login, as: MainLoginPage
  alias ChatWeb.ProxyLive.Page
  alias ChatWeb.State.ActorState
  alias ChatWeb.State.RoomMapState

  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.Proto

  def init(socket), do: socket |> assign(:room, nil)

  def handle_event(msg, _params, socket) do
    case msg do
      "went into lobby for  room/send-request" -> socket
    end
  end

  def store_key_copy_in_my_notes(socket, room_identity) do
    room_pub_key = room_identity |> Proto.Identify.pub_key()

    if not RoomMapState.has_room?(socket, room_pub_key) do
      my_identity = ActorState.my_identity(socket)
      my_notes_dialog = Dialogs.find_or_open(my_identity)
      server = socket |> Tools.SocketPrivate.get_private(:server)

      Task.start(fn ->
        room_identity
        |> Messages.RoomInvite.new()
        |> Chat.SignedParcel.wrap_dialog_message(my_notes_dialog, my_identity)
        |> Proxy.save_parcel(server, my_identity)
      end)
    end

    socket
  end

  def store_new(socket, new_room_identity) do
    socket
    |> store_key_copy_in_my_notes(new_room_identity)
    |> ActorState.add_room_identity(new_room_identity)
    |> RoomMapState.derive()
    |> MainLoginPage.store_new_room_on_client(new_room_identity)
    |> Page.Lobby.show_new_room(%{})
  end

  def close(%{assigns: %{room: nil}} = socket), do: socket
  def close(socket), do: socket
end
