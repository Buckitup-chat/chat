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
        socket |> AdminPanel.invite_user(hash |> decode)

      {"remove-user", %{"hash" => hash}} ->
        socket |> AdminPanel.remove_user(hash |> decode)

      {"remove-room", %{"hash" => hash}} ->
        socket |> AdminPanel.remove_room(hash |> decode)

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

      :refresh_rooms_and_users ->
        socket |> AdminPanel.refresh_rooms_and_users()
    end
  end

  defp decode(x), do: Base.decode16!(x, case: :lower)
end
