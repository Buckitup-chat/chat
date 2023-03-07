defmodule ChatWeb.MainLive.Page.AdminPanel do
  @moduledoc "Admin functions page"
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.RoomInviteIndex
  alias Phoenix.PubSub

  alias Chat.AdminRoom
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.User
  alias ChatWeb.Router.Helpers, as: Routes

  @incoming_topic "platform->chat"
  @outgoing_topic "chat->platform"

  def init(%{assigns: %{me: me}} = socket) do
    PubSub.subscribe(Chat.PubSub, @incoming_topic)

    me |> AdminRoom.visit()

    socket
    |> assign(:wifi_loaded, false)
    |> request_wifi_settings()
    |> assign_user_lists()
    |> assign_room_list()
  end

  def request_wifi_settings(socket) do
    request_platform(:get_wifi_settings)

    socket
  end

  def request_log(socket) do
    request_platform(:get_device_log)

    socket
  end

  def set_wifi(socket, ssid, password) do
    admin_room_identity = socket.room_map[AdminRoom.pub_key()]

    request_platform({:set_wifi, ssid, password})
    AdminRoom.store_wifi_password(password, admin_room_identity)

    socket
    |> assign(:wifi_password, password)
    |> assign(:wifi_ssid, ssid)
    |> assign(:wifi_loaded, false)
  end

  def show_error(socket, _error) do
    socket
  end

  def show_wifi_settings(%{assigns: %{room_map: rooms}} = socket, %{
        ssid: ssid,
        password: password
      }) do
    password =
      case AdminRoom.get_wifi_password(rooms[AdminRoom.pub_key()]) do
        nil -> password
        stored -> stored
      end

    socket
    |> assign(:wifi_password, password)
    |> assign(:wifi_ssid, ssid)
    |> assign(:wifi_loaded, true)
  end

  def confirm_wifi_updated(socket) do
    socket
    |> assign(:wifi_loaded, true)
  end

  def invite_user(%{assigns: %{me: me, room_map: rooms}} = socket, hash) do
    if new_user = User.by_id(hash) do
      dialog = Dialogs.find_or_open(me, new_user)

      AdminRoom.pub_key()
      |> then(&Map.get(rooms, &1))
      |> Messages.RoomInvite.new()
      |> Dialogs.add_new_message(me, dialog)
      |> RoomInviteIndex.add(dialog, me)
    end

    socket
  end

  def remove_user(socket, hash) do
    User.remove(hash)

    socket
    |> assign_user_lists()
  end

  def remove_room(socket, hash) do
    Rooms.delete(hash)

    socket
    |> assign_room_list()
  end

  def render_device_log(socket, log) do
    key =
      log
      |> Enum.map_join("\n", fn {level, {_module, msg, {{a, b, c}, {d, e, f, g}}, _extra}} ->
        date = NaiveDateTime.new!(a, b, c, d, e, f, g * 1000)
        "#{date} [#{level}] #{msg}"
      end)
      |> Chat.Broker.store()

    socket
    |> push_event("chat:redirect", %{url: Routes.temp_sync_url(socket, :device_log, key)})
  end

  def unmount_main(socket) do
    request_platform(:unmount_main)

    socket
  end

  def close(socket) do
    PubSub.unsubscribe(Chat.PubSub, @incoming_topic)

    socket
    |> assign(:admin_list, nil)
    |> assign(:user_list, nil)
  end

  defp request_platform(message),
    do: PubSub.broadcast(Chat.PubSub, @outgoing_topic, message)

  defp assign_user_lists(socket) do
    admin_map =
      AdminRoom.admin_list()
      |> Enum.map(&{&1.hash, &1})
      |> Map.new()

    full_user_list = User.list()

    user_list =
      full_user_list
      |> Enum.reject(fn %{hash: hash} -> admin_map[hash] end)

    socket
    |> assign(:admin_list, admin_map |> Map.values())
    |> assign(:user_list, user_list)
    |> assign(:full_user_list, full_user_list)
  end

  defp assign_room_list(%{assigns: %{room_map: rooms}} = socket) do
    {my, other} = Rooms.list(rooms)
    room_list = my ++ other

    socket
    |> assign(:room_list, room_list)
  end
end
