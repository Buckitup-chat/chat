defmodule ChatWeb.MainLive.Page.Room.Requests do
  @moduledoc """
  Room membership: pending join requests of a request-type room (`:room_requests` assign,
  approval) and inviting users into the room via a dialog message.

  Part of the `ChatWeb.MainLive.Page.Room` namespace.
  """

  import ChatWeb.LiveHelpers, only: [show_modal: 1, open_modal: 3, send_js: 2]
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.RoomInviteIndex
  alias Chat.Rooms
  alias Chat.Rooms.RoomRequest
  alias Chat.User
  alias Chat.User.UsersBroker

  def approve_request(%{assigns: %{room_identity: room_identity}} = socket, user_key) do
    room = Rooms.approve_request(room_identity |> Identity.pub_key(), user_key, room_identity)
    Rooms.RoomsBroker.put(room)

    case Rooms.get_request(room, user_key) do
      %RoomRequest{ciphered_room_identity: ciphered} when is_bitstring(ciphered) ->
        Chat.Broadcast.room_request_approved(user_key, room.pub_key, ciphered)

      _ ->
        :ok
    end

    socket
    |> assign_requests([user_key])
    |> assign(:room_requests_update_mode, "ignore")
    |> push_event("put-flash", %{key: :info, message: "Request approved!"})
  end

  def assign_requests(socket, to_ignore \\ [])

  def assign_requests(%{assigns: %{room: %{type: :request} = room}} = socket, to_ignore) do
    request_list =
      room.pub_key
      |> Rooms.list_pending_requests()
      |> Enum.reject(fn %RoomRequest{requester_key: pub_key} -> pub_key in to_ignore end)
      |> Enum.map(fn %RoomRequest{requester_key: pub_key} -> User.by_id(pub_key) end)
      |> Enum.reject(&is_nil/1)

    socket
    |> assign(:room_requests, request_list)
    |> assign(:room_requests_update_mode, "replace")
  end

  def assign_requests(socket, _), do: socket |> assign(:room_requests, [])

  def maybe_update_requests(socket, message) do
    message.type
    |> case do
      :request -> socket |> assign_requests()
      _ -> socket
    end
  end

  def open_invite_list(%{assigns: %{db_status: %{writable: :no}}} = socket, _) do
    socket
    |> send_js(show_modal("restrict-write-actions"))
  end

  def open_invite_list(%{assigns: %{my_id: id}} = socket, modal) do
    users = UsersBroker.list() |> Enum.reject(fn user -> user.pub_key == id end)

    if users |> length() > 0 do
      socket |> open_modal(modal, %{users: users})
    else
      socket
    end
  end

  def invite_user(
        %{
          assigns: %{
            room: %{name: room_name, pub_key: room_pub_key},
            room_identity: identity,
            me: me
          }
        } = socket,
        user_key
      ) do
    dialog = Dialogs.find_or_open(me, user_key |> User.by_id())

    identity
    |> Map.put(:name, room_name)
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(me, dialog)
    |> RoomInviteIndex.add(dialog, me, room_pub_key)
    |> Chat.Broadcast.new_dialog_message(dialog)

    socket
    |> push_event("put-flash", %{key: :info, message: "Invitation Sent!"})
  rescue
    _ -> socket
  end
end
