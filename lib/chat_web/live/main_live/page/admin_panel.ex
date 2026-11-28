defmodule ChatWeb.MainLive.Page.AdminPanel do
  @moduledoc """
  Admin functions page: opening and closing the panel (PubSub topics, free space
  poller), the platform request channel and network sync status updates. Also the
  stable entry point for the admin routers and components, which delegates to:

  - `ChatWeb.MainLive.Page.AdminPanel.Device` — WiFi, GPIO, LAN, device log, weight sensor
  - `ChatWeb.MainLive.Page.AdminPanel.Members` — user/room lists, admin invites, removals
  - `ChatWeb.MainLive.Page.AdminPanel.CargoUser` — creating the cargo user
  - `ChatWeb.MainLive.Page.AdminPanel.Firmware` — firmware upgrade modals and progress
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [send_update: 2]

  alias Chat.AdminRoom
  alias Chat.Db.FreeSpacesPoller
  alias Chat.Db.FreeSpacesSupervisor
  alias ChatWeb.MainLive.Page.AdminPanel.CargoUser
  alias ChatWeb.MainLive.Page.AdminPanel.Device
  alias ChatWeb.MainLive.Page.AdminPanel.Firmware
  alias ChatWeb.MainLive.Page.AdminPanel.Members
  alias Phoenix.PubSub

  @admin_topic "chat::admin"
  @incoming_topic Application.compile_env!(:chat, :topic_from_platform)
  @outgoing_topic Application.compile_env!(:chat, :topic_to_platform)

  defdelegate request_wifi_settings(socket), to: Device
  defdelegate request_gpio24_impedance_status(socket), to: Device
  defdelegate request_log(socket), to: Device
  defdelegate set_wifi(socket, ssid, password), to: Device
  defdelegate show_error(socket, error), to: Device
  defdelegate show_internal_db_unavailable(socket, status), to: Device
  defdelegate show_wifi_settings(socket, settings), to: Device
  defdelegate confirm_wifi_updated(socket), to: Device
  defdelegate update_lan_settings(changes), to: Device
  defdelegate toggle_gpio24_impendance(socket), to: Device
  defdelegate set_gpio24_impedance_status(socket, status), to: Device
  defdelegate render_device_log(socket, log), to: Device
  defdelegate unmount_main(socket), to: Device
  defdelegate connect_to_weight_sensor(socket, device_params, opts), to: Device
  defdelegate weight_sensor_connection_status(socket, status), to: Device

  defdelegate show_user_invite_modal(socket, hash, modal), to: Members
  defdelegate confirm_user_invite(socket, hash), to: Members
  defdelegate remove_user(socket, hash), to: Members
  defdelegate remove_room(socket, hash), to: Members
  defdelegate refresh_rooms_and_users(socket), to: Members

  defdelegate create_cargo_user(socket, cargo_user_data), to: CargoUser

  defdelegate upgrade_firmware_confirmation(socket), to: Firmware
  defdelegate upgrade_firmware(socket), to: Firmware
  defdelegate notify_firmware_upgraded(socket), to: Firmware
  defdelegate github_upgrade_firmware_confirmation(socket, release), to: Firmware
  defdelegate github_upgrade_firmware(socket), to: Firmware
  defdelegate github_firmware_upgrade_response(socket, message), to: Firmware

  def init(%{assigns: %{me: me}} = socket) do
    PubSub.subscribe(Chat.PubSub, @admin_topic)
    PubSub.subscribe(Chat.PubSub, @incoming_topic)
    PubSub.subscribe(Chat.PubSub, Chat.NetworkSynchronization.notification_topic())

    start_poller(me)

    PubSub.subscribe(Chat.PubSub, FreeSpacesPoller.channel())

    me |> AdminRoom.visit()

    socket
    |> assign(:wifi_loaded, false)
    |> Device.request_wifi_settings()
    |> Device.request_gpio24_impedance_status()
    |> Members.assign_user_lists()
    |> Members.assign_room_list()
    |> assign(:free_spaces, FreeSpacesPoller.get_info())
    |> assign(:cargo_user, AdminRoom.get_cargo_user())
  end

  def int(socket) do
    socket
    |> assign(:need_login, true)
    |> assign(:handshaked, false)
  end

  def set_free_spaces(socket, free_spaces), do: socket |> assign(:free_spaces, free_spaces)

  def send_network_source_list_update(socket, source_id, status) do
    send_update(ChatWeb.MainLive.Admin.NetworkSourceList,
      id: :network_sources,
      status_update: {source_id, status}
    )

    socket
  end

  def send_electric_sync_update(socket, peer_url, shape, status) do
    send_update(ChatWeb.MainLive.Admin.NetworkSourceList,
      id: :network_sources,
      electric_status_update: {peer_url, shape, status}
    )

    socket
  end

  def close(%{assigns: %{me: %{name: admin}}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, @admin_topic)
    PubSub.unsubscribe(Chat.PubSub, @incoming_topic)
    PubSub.unsubscribe(Chat.PubSub, Chat.NetworkSynchronization.notification_topic())
    PubSub.unsubscribe(Chat.PubSub, FreeSpacesPoller.channel())

    FreeSpacesPoller.leave(admin)

    socket
    |> assign(:admin_list, nil)
    |> assign(:user_list, nil)
  end

  def request_platform(message),
    do: PubSub.broadcast(Chat.PubSub, @outgoing_topic, message)

  def stop_poller do
    case FreeSpacesPoller |> Process.whereis() do
      nil -> nil
      pid -> DynamicSupervisor.terminate_child(FreeSpacesSupervisor, pid)
    end
  end

  defp start_poller(%{name: admin}) do
    child_spec = FreeSpacesPoller.child_spec(name: FreeSpacesPoller, admin: admin)

    start_result = DynamicSupervisor.start_child(FreeSpacesSupervisor, child_spec)

    case start_result do
      {:ok, _} -> :ok
      _ -> FreeSpacesPoller.join(admin)
    end
  end
end
