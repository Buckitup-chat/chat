defmodule ChatWeb.MainLive.Page.AdminPanelRouter do
  @moduledoc "Route admin panel events"

  require Logger

  alias ChatWeb.MainLive.Page

  #
  # LiveView events
  #

  def event(socket, event) do
    case event do
      {"wifi-submit", %{"ssid" => ssid, "password" => password}} ->
        socket |> Page.AdminPanel.set_wifi(ssid |> String.trim(), password |> String.trim())

      {"invite-new-user", %{"hash" => hash}} ->
        socket |> Page.AdminPanel.invite_user(hash)

      {"remove-user", %{"hash" => hash}} ->
        socket |> Page.AdminPanel.remove_user(hash)

      {"remove-room", %{"hash" => hash}} ->
        socket |> Page.AdminPanel.remove_room(hash)

      {"device-log", _} ->
        socket |> Page.AdminPanel.request_log()
    end
  end

  #
  # Internal events
  #

  def info(socket, message) do
    Logger.warn("Chat receives: " <> inspect(message, pretty: true))

    case message do
      {:error, reason} ->
        socket |> Page.AdminPanel.show_error(reason)

      {:wifi_settings, settings} ->
        socket |> Page.AdminPanel.show_wifi_settings(settings)

      {:updated_wifi_settings, _} ->
        socket |> Page.AdminPanel.confirm_wifi_updated()

      {:device_log, log} ->
        socket |> Page.AdminPanel.render_device_log(log)
    end
  end
end
