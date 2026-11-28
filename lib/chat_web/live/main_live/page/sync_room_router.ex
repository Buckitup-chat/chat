defmodule ChatWeb.MainLive.Page.SyncRoomRouter do
  @moduledoc """
  Cargo room and USB drive dump room handling of `ChatWeb.MainLive.Index`: PubSub
  subscription on mount, `cargo:*` / `dump:*` events and `Chat.Sync.CargoRoom` /
  `Chat.Sync.UsbDriveDumpRoom` updates.

  Activating a cargo room invites every cargo checkpoint into it.

  Siblings: `LoginRouter`, `LogoutRouter`, `LobbyRouter`.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Chat.Admin.CargoSettings
  alias Chat.{Dialogs, Identity, Messages, RoomInviteIndex}
  alias Chat.Rooms.Room
  alias Chat.Sync.{CargoRoom, UsbDriveDumpRoom}
  alias ChatWeb.MainLive.Page
  alias Phoenix.PubSub

  @doc "Subscribe to cargo and dump room updates and assign their current state"
  def init(socket) do
    socket
    |> assign_cargo_room()
    |> assign_usb_drive_dump_room()
  end

  defp assign_cargo_room(socket) do
    PubSub.subscribe(Chat.PubSub, "chat::cargo_room")

    assign(socket, :cargo_room, CargoRoom.get())
  end

  defp assign_usb_drive_dump_room(socket) do
    PubSub.subscribe(Chat.PubSub, "chat::usb_drive_dump_room")

    assign(socket, :usb_drive_dump_room, UsbDriveDumpRoom.get())
  end

  #
  # LiveView events
  #

  def event(socket, event) do
    case event do
      {"cargo:activate", _} ->
        socket |> tap(&activate_cargo_room/1)

      {"cargo:remove", _} ->
        socket |> tap(fn _ -> CargoRoom.remove() end)

      {"dump:activate", _} ->
        socket |> tap(&activate_dump_room/1)

      {"dump:remove", _} ->
        socket |> tap(fn _ -> UsbDriveDumpRoom.remove() end)
    end
  end

  defp activate_cargo_room(socket) do
    UsbDriveDumpRoom.remove()
    CargoRoom.activate(socket.assigns.room.pub_key)

    %CargoSettings{} = cargo_settings = socket.assigns.cargo_settings
    %Identity{} = me = socket.assigns.me
    %Identity{} = room_identity = socket.assigns.room_identity
    %Room{} = room = socket.assigns.room

    cargo_settings.checkpoints
    |> Enum.each(fn checkpoint ->
      dialog = Dialogs.open(me, checkpoint)

      if not_invited?(dialog, me, room_identity) do
        invite_checkpoint(room_identity, room, me, dialog)
      end
    end)
  end

  defp not_invited?(dialog, me, room_identity) do
    Dialogs.read(dialog, me)
    |> Stream.filter(fn %{type: type} -> type == :room_invite end)
    |> Stream.filter(fn message ->
      identity = Dialogs.extract_invite_room_identity(message)
      identity.public_key == room_identity.public_key
    end)
    |> Enum.to_list()
    |> Enum.empty?()
  end

  defp activate_dump_room(socket) do
    CargoRoom.remove()

    UsbDriveDumpRoom.activate(
      socket.assigns.room.pub_key,
      socket.assigns.room_identity,
      socket.assigns.monotonic_offset
    )
  end

  #
  # Process messages
  #

  def info(socket, message) do
    case message do
      {:maybe_activate_cargo_room, true, %Room{} = room, room_identity} ->
        socket |> tap(&activate_new_cargo_room(&1, room, room_identity))

      {:maybe_activate_cargo_room, _cargo?, _room, _room_identity} ->
        socket

      {:update_cargo_room, cargo_room} ->
        socket
        |> assign(:cargo_room, cargo_room)
        |> refresh_room_actions()

      {:update_usb_drive_dump_progress, dump_room} ->
        socket |> assign(:usb_drive_dump_room, dump_room)

      {:update_usb_drive_dump_room, dump_room} ->
        socket
        |> assign(:usb_drive_dump_room, dump_room)
        |> refresh_room_actions()
    end
  end

  defp activate_new_cargo_room(socket, room, room_identity) do
    UsbDriveDumpRoom.remove()
    CargoRoom.activate(room.pub_key)

    %CargoSettings{} = cargo_settings = socket.assigns.cargo_settings
    %Identity{} = me = socket.assigns.me

    cargo_settings.checkpoints
    |> Enum.each(fn checkpoint ->
      invite_checkpoint(room_identity, room, me, Dialogs.find_or_open(me, checkpoint))
    end)
  end

  defp refresh_room_actions(socket) do
    socket
    |> Page.Room.maybe_enable_cargo()
    |> Page.Room.maybe_enable_usb_drive_dump()
  end

  # --- shared helpers ---

  defp invite_checkpoint(room_identity, room, me, dialog) do
    room_identity
    |> Map.put(:name, room.name)
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(me, dialog)
    |> RoomInviteIndex.add(dialog, me, room.pub_key)
  end
end
