defmodule ChatWeb.MainLive.Page.AdminPanel do
  @moduledoc "Admin functions page"
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3, send_update: 2]
  import ChatWeb.LiveHelpers, only: [open_modal: 2, close_modal: 1]

  alias Chat.RoomInviteIndex
  alias Phoenix.PubSub

  alias Chat.AdminRoom
  alias Chat.ChunkedFiles
  alias Chat.ChunkedFilesMultisecret
  alias Chat.Db.{FreeSpacesPoller, FreeSpacesSupervisor}
  alias Chat.Dialogs
  alias Chat.FileIndex
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.Rooms.RoomsBroker
  alias Chat.Upload.UploadKey
  alias Chat.User
  alias Chat.User.UsersBroker
  alias ChatWeb.MainLive.Admin.CargoWeightSensorForm
  alias ChatWeb.MainLive.Admin.FirmwareUpgradeForm
  alias ChatWeb.Router.Helpers, as: Routes

  @admin_topic "chat::admin"
  @incoming_topic "platform->chat"
  @outgoing_topic "chat->platform"

  def init(%{assigns: %{me: me}} = socket) do
    PubSub.subscribe(Chat.PubSub, @admin_topic)
    PubSub.subscribe(Chat.PubSub, @incoming_topic)

    start_poller(me)

    PubSub.subscribe(Chat.PubSub, FreeSpacesPoller.channel())

    me |> AdminRoom.visit()

    socket
    |> assign(:wifi_loaded, false)
    |> request_wifi_settings()
    |> request_gpio24_impedance_status()
    |> assign_user_lists()
    |> assign_room_list()
    |> assign(:free_spaces, FreeSpacesPoller.get_info())
    |> assign(:cargo_user, AdminRoom.get_cargo_user())
  end

  def int(socket) do
    socket
    |> assign(:need_login, true)
    |> assign(:handshaked, false)
  end

  def request_wifi_settings(socket) do
    request_platform(:get_wifi_settings)

    socket
  end

  def request_gpio24_impedance_status(socket) do
    request_platform(:get_gpio24_impedance_status)

    socket
  end

  def request_log(socket) do
    request_platform(:get_device_log)

    socket
  end

  def set_wifi(%{assigns: %{room_map: rooms}} = socket, ssid, password) do
    admin_room_identity = rooms[AdminRoom.pub_key()]

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

  def toggle_gpio24_impendance(socket) do
    request_platform(:toggle_gpio24_impendance)

    socket
  end

  def set_gpio24_impedance_status(socket, 0) do
    socket
    |> assign(:gpio24_impedance_status, "Off")
  end

  def set_gpio24_impedance_status(socket, 1) do
    socket
    |> assign(:gpio24_impedance_status, "On")
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
    hash
    |> tap(&User.remove/1)
    |> tap(&UsersBroker.forget/1)

    socket
    |> assign_user_lists()
  end

  def remove_room(socket, hash) do
    hash
    |> tap(&Rooms.delete/1)
    |> tap(&RoomsBroker.forget/1)

    socket
    |> assign_room_list()
  end

  def render_device_log(socket, {nil, log}), do: render_device_log(socket, log)

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

  def set_free_spaces(socket, free_spaces), do: socket |> assign(:free_spaces, free_spaces)

  def refresh_rooms_and_users(socket) do
    socket
    |> assign_room_list()
    |> assign_user_lists()
  end

  def close(%{assigns: %{me: %{name: admin}}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, @admin_topic)
    PubSub.unsubscribe(Chat.PubSub, @incoming_topic)
    PubSub.unsubscribe(Chat.PubSub, FreeSpacesPoller.channel())

    FreeSpacesPoller.leave(admin)

    socket
    |> assign(:admin_list, nil)
    |> assign(:user_list, nil)
  end

  def connect_to_weight_sensor(socket, name, opts) do
    request_platform({:connect_to_weight_sensor, name, opts})

    socket
  end

  def weight_sensor_connection_status(socket, status) do
    status_str = if status == :ok, do: "Established", else: "Failed"

    send_update(CargoWeightSensorForm,
      id: :cargo_weight_sensor_form,
      connection_status: status_str
    )

    socket
  end

  def create_cargo_user(socket, {identity, backup_content, backup_entry}) do
    cargo_user =
      identity
      |> tap(&AdminRoom.store_cargo_user/1)
      |> tap(&User.register/1)
      |> tap(&UsersBroker.put/1)

    AdminRoom.admin_list()
    |> Enum.each(fn admin_card ->
      dialog = %{b_key: b_key} = Dialogs.open(cargo_user, admin_card)
      destination = %{dialog: dialog, pub_key: Base.encode16(b_key, case: :lower), type: :dialog}
      file_key = UploadKey.new(destination, cargo_user.public_key, backup_entry)
      file_secret = ChunkedFiles.new_upload(file_key)

      :ok = save_file({file_key, backup_content}, {backup_entry.client_size, file_secret})

      now = DateTime.utc_now() |> DateTime.to_unix()

      text =
        "The backup `#{backup_entry.client_name}` is not encrypted. Do not share it with anyone."

      %Messages.Text{text: text, timestamp: now}
      |> Dialogs.add_new_message(identity, dialog)
      |> MemoIndex.add(dialog, identity)

      {_index, msg} =
        backup_entry
        |> Messages.File.new(file_key, file_secret, now)
        |> Dialogs.add_new_message(cargo_user, dialog)

      FileIndex.save(file_key, dialog.a_key, msg.id, file_secret)
      FileIndex.save(file_key, dialog.b_key, msg.id, file_secret)
    end)

    socket
    |> assign(:cargo_user, cargo_user)
  end

  def upgrade_firmware_confirmation(socket) do
    socket
    |> open_modal(ChatWeb.MainLive.Modals.ConfirmFirmwareUpgrade)
  end

  def upgrade_firmware(socket) do
    send_update(FirmwareUpgradeForm, id: :firmware_upgrade_form, step: :upgrade)

    socket
    |> close_modal()
  end

  def notify_firmware_upgraded(socket) do
    send_update(FirmwareUpgradeForm, id: :firmware_upgrade_form, substep: :done)

    socket
    |> put_flash(:info, "Firmware upgraded")
  end

  defp save_file({file_key, content}, {size, file_secret}) do
    ChunkedFilesMultisecret.generate(file_key, size, file_secret)
    ChunkedFiles.save_upload_chunk(file_key, {0, max(size - 1, 0)}, size, content)
  end

  defp request_platform(message),
    do: PubSub.broadcast(Chat.PubSub, @outgoing_topic, message)

  defp assign_user_lists(socket) do
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

  defp assign_room_list(%{assigns: %{room_map: rooms}} = socket) do
    {my, other} = RoomsBroker.list(rooms)
    room_list = my ++ other

    socket
    |> assign(:room_list, room_list)
  end

  defp start_poller(%{name: admin}) do
    child_spec = FreeSpacesPoller.child_spec(name: FreeSpacesPoller, admin: admin)

    start_result = DynamicSupervisor.start_child(FreeSpacesSupervisor, child_spec)

    case start_result do
      {:ok, _} -> :ok
      _ -> FreeSpacesPoller.join(admin)
    end
  end

  def stop_poller do
    case FreeSpacesPoller |> Process.whereis() do
      nil -> nil
      pid -> DynamicSupervisor.terminate_child(FreeSpacesSupervisor, pid)
    end
  end
end
