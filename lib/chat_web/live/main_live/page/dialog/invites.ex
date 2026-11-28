defmodule ChatWeb.MainLive.Page.Dialog.Invites do
  @moduledoc """
  Room invites received in a dialog: accepting one, accepting and opening the room,
  accepting all, and refreshing the invite navigation.

  Part of the `ChatWeb.MainLive.Page.Dialog` namespace.
  """

  import ChatWeb.MainLive.Page.Shared, only: [render_to_html_string: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.AdminRoom
  alias Chat.Card
  alias Chat.Content.RoomInvites
  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Rooms
  alias Chat.Sync.DbBrokers
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Page

  def accept_room_invite(
        %{assigns: %{room_map: room_map}} = socket,
        %{type: :room_invite, content: content} = msg,
        render_fun
      ) do
    new_room_identity =
      content
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    if Map.has_key?(room_map, Identity.pub_key(new_room_identity)) do
      socket
    else
      socket
      |> Page.Room.store_new(new_room_identity)
      |> update_invite_navigation(msg, new_room_identity, render_fun)
    end
  rescue
    _ -> socket
  end

  def accept_room_invite(%{assigns: %{me: me, dialog: dialog}} = socket, message_id, render_fun) do
    socket
    |> accept_room_invite(Dialogs.read_message(dialog, message_id, me), render_fun)
  end

  def accept_room_invite_and_open_room(
        %{assigns: %{me: me, dialog: dialog, room_map: room_map}} = socket,
        message_id
      ) do
    new_room_identity =
      Dialogs.read_message(dialog, message_id, me)
      |> then(fn %{type: :room_invite, content: json} -> json end)
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    socket =
      if Map.has_key?(room_map, Identity.pub_key(new_room_identity)) do
        socket
      else
        socket
        |> Page.Room.store_new(new_room_identity)
      end
      |> Page.Dialog.close()

    if new_room_identity.public_key == AdminRoom.pub_key() do
      socket
      |> Page.Lobby.switch_lobby_mode("admin")
      |> tap(fn _ -> DbBrokers.broadcast_refresh() end)
    else
      socket
      |> Page.Room.init(
        {new_room_identity, new_room_identity |> Identity.pub_key() |> Rooms.get()}
      )
    end
  rescue
    _ -> socket
  end

  def accept_all_room_invites(%{assigns: %{dialog: dialog, me: me}} = socket) do
    Dialogs.list_room_invites(dialog, me)
    |> Enum.reverse()
    |> Enum.each(fn invite ->
      send(self(), {:dialog, {:accept_room_invite, invite}})
    end)

    socket
  end

  defp update_invite_navigation(
         %{assigns: %{room_map: room_map}} = socket,
         msg,
         room_identity,
         render_fun
       ) do
    room_hash = room_identity |> Card.from_identity() |> Enigma.short_hash()
    room_key = room_identity |> Identity.pub_key()

    socket
    |> push_event("chat:bulk-change", %{
      to: ".x-invite-navigation[data-room='#{room_hash}']",
      content:
        render_to_html_string(
          %{msg: msg, room_key: room_key, room_keys: Map.keys(room_map)},
          render_fun
        )
    })
  end
end
