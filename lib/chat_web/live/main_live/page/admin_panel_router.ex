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
    end
  end
end
