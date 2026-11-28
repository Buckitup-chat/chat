defmodule ChatWeb.MainLive.Page.AdminPanel.Members do
  @moduledoc """
  Users and rooms in the admin panel: the admin/user/room lists, inviting a user to
  the admin room, removing users and rooms, refreshing the lists.

  Part of the `ChatWeb.MainLive.Page.AdminPanel` namespace.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [send_update: 2]
  import ChatWeb.LiveHelpers, only: [open_modal: 3, close_modal: 1]

  alias Chat.AdminRoom
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.RoomInviteIndex
  alias Chat.Rooms
  alias Chat.Rooms.RoomsBroker
  alias Chat.Sync.DbBrokers
  alias Chat.User
  alias Chat.User.UsersBroker
  alias ChatWeb.MainLive.Admin.CargoCheckpointsForm
  alias ChatWeb.MainLive.Admin.CargoUserData

  def show_user_invite_modal(%{assigns: %{user_list: users}} = socket, hash, modal) do
    socket
    |> open_modal(modal, %{user: users |> Enum.find(fn card -> card.pub_key == hash end)})
  end

  def confirm_user_invite(%{assigns: %{me: me, room_map: rooms}} = socket, hash) do
    if new_user = User.by_id(hash) do
      dialog = Dialogs.find_or_open(me, new_user)

      AdminRoom.pub_key()
      |> then(&Map.get(rooms, &1))
      |> Messages.RoomInvite.new()
      |> Dialogs.add_new_message(me, dialog)
      |> RoomInviteIndex.add(dialog, me, AdminRoom.pub_key())
    end

    socket
    |> close_modal()
  end

  def remove_user(socket, hash) do
    hash
    |> tap(&User.remove/1)
    |> tap(&UsersBroker.forget/1)
    |> tap(fn _ -> DbBrokers.broadcast_refresh() end)

    socket
  end

  def remove_room(socket, hash) do
    hash
    |> tap(&Rooms.delete/1)
    |> tap(&RoomsBroker.forget/1)
    |> tap(fn _ -> DbBrokers.broadcast_refresh() end)

    socket
  end

  def refresh_rooms_and_users(socket) do
    socket
    |> assign_room_list()
    |> assign_user_lists()
    |> tap(fn _ ->
      send_update(CargoCheckpointsForm, id: :cargo_checkpoints_form, action: :refresh)
      send_update(CargoUserData, id: :cargo_user_data, cargo_user: AdminRoom.get_cargo_user())
    end)
  end

  def assign_user_lists(socket) do
    admin_map =
      AdminRoom.admin_list()
      |> Enum.map(&{&1.hash, &1})
      |> Map.new()

    full_user_list = UsersBroker.list()

    user_list =
      full_user_list
      |> Enum.reject(fn %{hash: hash} -> admin_map[hash] end)

    socket
    |> assign(:admin_list, admin_map |> Map.values())
    |> assign(:user_list, user_list)
    |> assign(:full_user_list, full_user_list)
  end

  def assign_room_list(%{assigns: %{room_map: rooms}} = socket) do
    {my, other} = RoomsBroker.list(rooms)
    room_list = my ++ other

    socket
    |> assign(:room_list, room_list)
  end
end
