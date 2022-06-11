defmodule ChatWeb.MainLive.Page.AdminPanel do
  @moduledoc "Admin functions page"
  import Phoenix.LiveView, only: [assign: 3]

  alias Phoenix.PubSub

  alias Chat.AdminRoom
  alias Chat.User

  @incoming_topic "platform->chat"
  @outgoing_topic "chat->platform"

  def init(%{assigns: %{me: me}} = socket) do
    PubSub.subscribe(Chat.PubSub, @incoming_topic)

    me |> AdminRoom.visit()

    socket
    |> assign(:wifi_loaded, false)
    |> assign_user_lists()
    |> request_wifi_settings()
  end

  def request_wifi_settings(socket) do
    request_platform(:get_wifi_settings)

    socket
  end

  def set_wifi(socket, ssid, password) do
    request_platform({:set_wifi, ssid, password})

    socket
    |> assign(:wifi_password, password)
    |> assign(:wifi_ssid, ssid)
    |> assign(:wifi_loaded, false)
  end

  def show_error(socket, _error) do
    socket
  end

  def show_wifi_settings(socket, %{ssid: ssid, password: password}) do
    socket
    |> assign(:wifi_password, password)
    |> assign(:wifi_ssid, ssid)
    |> assign(:wifi_loaded, true)
  end

  def confirm_wifi_updated(socket) do
    socket
    |> assign(:wifi_loaded, true)
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

    user_list =
      User.list()
      |> Enum.reject(fn %{hash: hash} -> admin_map[hash] end)

    socket
    |> assign(:admin_list, admin_map |> Map.values())
    |> assign(:user_list, user_list)
  end
end
