defmodule ChatWeb.MainLive.Page.Room.SyncState do
  @moduledoc """
  Whether the open room can be cargo-synced or USB-drive-dumped right now
  (`:cargo_sync` / `:usb_drive_dump` assigns), and the USB dump progress subscription.

  Part of the `ChatWeb.MainLive.Page.Room` namespace; called on room init and by the
  lobby / sync room routers when cargo or dump state changes.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Chat.Admin.MediaSettings
  alias Chat.Rooms.{Registry, Room}
  alias Chat.Sync.{CargoRoom, UsbDriveDumpRoom}

  alias Phoenix.PubSub

  @usb_drive_dump_progress_topic "chat::usb_drive_dump_progress"

  def usb_drive_dump_progress_topic, do: @usb_drive_dump_progress_topic

  def maybe_enable_cargo(socket) do
    %MediaSettings{} = media_settings = socket.assigns.media_settings
    room = socket.assigns[:room]

    if media_settings.functionality == :cargo and not is_nil(room) do
      cargo_sync =
        cond do
          match?(%UsbDriveDumpRoom{status: :dumping}, socket.assigns[:usb_drive_dump_room]) ->
            :disabled

          match?(
            %CargoRoom{pub_key: pub_key, status: status}
            when pub_key == room.pub_key or status == :syncing,
            socket.assigns[:cargo_room]
          ) ->
            :disabled

          !has_unique_name(room) ->
            :duplicate_name

          true ->
            :enabled
        end

      assign(socket, :cargo_sync, cargo_sync)
    else
      assign(socket, :cargo_sync, nil)
    end
  end

  def maybe_enable_usb_drive_dump(%{assigns: %{room: room}} = socket) when not is_nil(room) do
    PubSub.unsubscribe(Chat.PubSub, @usb_drive_dump_progress_topic)

    usb_drive_dump =
      cond do
        match?(%CargoRoom{status: :syncing}, socket.assigns[:cargo_room]) ->
          :disabled

        match?(
          %UsbDriveDumpRoom{pub_key: pub_key, status: status}
          when pub_key == room.pub_key or status == :dumping,
          socket.assigns[:usb_drive_dump_room]
        ) ->
          PubSub.subscribe(Chat.PubSub, @usb_drive_dump_progress_topic)
          :disabled

        true ->
          :enabled
      end

    assign(socket, :usb_drive_dump, usb_drive_dump)
  end

  def maybe_enable_usb_drive_dump(socket), do: socket

  defp has_unique_name(%Room{} = room) do
    Registry.all()
    |> Enum.any?(fn {_room_pub_key, %Room{} = other_room} ->
      other_room.name == room.name and other_room.pub_key != room.pub_key
    end)
    |> Kernel.not()
  end
end
