defmodule ChatWeb.MainLive.Page.AdminPanelRouter do
  @moduledoc "Route admin panel events"

  require Logger

  alias ChatWeb.MainLive.Page.AdminPanel

  #
  # LiveView events
  #

  def event(socket, event) do
    case event do
      {"wifi-submit", %{"ssid" => ssid, "password" => password}} ->
        socket |> AdminPanel.set_wifi(ssid |> String.trim(), password |> String.trim())

      {"invite-new-user", %{"hash" => hash}} ->
        socket |> AdminPanel.invite_user(hash)

      {"remove-user", %{"hash" => hash}} ->
        socket |> AdminPanel.remove_user(hash)

      {"remove-room", %{"hash" => hash}} ->
        socket |> AdminPanel.remove_room(hash)

      {"device-log", _} ->
        socket |> AdminPanel.request_log()

      {"unmount-main", _} ->
        socket |> AdminPanel.unmount_main()
    end
  end

  #
  # Internal events
  #

  def info(socket, message) do
    # Logger.warn("Chat receives: " <> inspect(message, pretty: true))

    case message do
      {:error, reason} ->
        socket |> AdminPanel.show_error(reason)

      {:wifi_settings, settings} ->
        socket |> AdminPanel.show_wifi_settings(settings)

      {:updated_wifi_settings, _} ->
        socket |> AdminPanel.confirm_wifi_updated()

      {:device_log, log} ->
        socket |> AdminPanel.render_device_log(log)

      {:unmounted_main, _} ->
        socket
    end
  end
end
