defmodule ChatWeb.MainLive.Page.AdminPanel.Device do
  @moduledoc """
  Device settings in the admin panel, all talking to the platform through
  `ChatWeb.MainLive.Page.AdminPanel.request_platform/1`: WiFi, GPIO24 impedance, LAN
  settings, device log, unmounting the main drive, the cargo weight sensor, and the
  platform errors shown to the admin.

  Part of the `ChatWeb.MainLive.Page.AdminPanel` namespace.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3, send_update: 2]

  alias Chat.AdminRoom
  alias ChatWeb.MainLive.Admin.CargoWeightSensorForm
  alias ChatWeb.MainLive.Admin.LanSettings
  alias ChatWeb.MainLive.Page.AdminPanel
  alias ChatWeb.Router.Helpers, as: Routes

  def request_wifi_settings(socket) do
    AdminPanel.request_platform(:get_wifi_settings)

    socket
  end

  def request_gpio24_impedance_status(socket) do
    AdminPanel.request_platform(:get_gpio24_impedance_status)

    socket
  end

  def request_log(socket) do
    AdminPanel.request_platform(:get_device_log)

    socket
  end

  def set_wifi(%{assigns: %{room_map: rooms}} = socket, ssid, password) do
    admin_room_identity = rooms[AdminRoom.pub_key()]

    AdminPanel.request_platform({:set_wifi, ssid, password})
    AdminRoom.store_wifi_password(password, admin_room_identity)

    socket
    |> assign(:wifi_password, password)
    |> assign(:wifi_ssid, ssid)
    |> assign(:wifi_loaded, false)
  end

  def show_error(socket, _error) do
    socket
  end

  # Platform gave up waiting for the internal DB, so USB drives are mounted but
  # never classified - without this the admin only sees a drive that does nothing.
  def show_internal_db_unavailable(socket, %{cubdb: cubdb?, pg: pg?}) do
    socket
    |> put_flash(
      :error,
      "Internal database did not start (CubDB #{db_state(cubdb?)}, PostgreSQL #{db_state(pg?)}). " <>
        "USB drives are not recognized until it does."
    )
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

  def update_lan_settings(changes) do
    send_update(LanSettings, changes |> Keyword.merge(id: :lan_settings))
  end

  def toggle_gpio24_impendance(socket) do
    AdminPanel.request_platform(:toggle_gpio24_impendance)

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
    AdminPanel.request_platform(:unmount_main)

    socket
  end

  def connect_to_weight_sensor(socket, device_params, opts) do
    AdminPanel.request_platform({:connect_to_weight_sensor, device_params, opts})

    socket
  end

  def weight_sensor_connection_status(socket, status) do
    case status do
      {:ok, msg} ->
        [connection_status: "Established", test_message: msg]

      _ ->
        [connection_status: "Failed", test_message: ""]
    end
    |> Keyword.put(:id, :cargo_weight_sensor_form)
    |> then(&send_update(CargoWeightSensorForm, &1))

    socket
  end

  defp db_state(true), do: "ready"
  defp db_state(false), do: "down"
end
