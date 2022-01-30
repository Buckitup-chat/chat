defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  alias Chat.User

  @local_store_key "buckitUp-chat-auth"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      params = get_connect_params(socket)

      socket
      |> assign(
        locale: params["locale"] || "en",
        timezone: params["timezone"] || "UTC",
        timezone_offset: params["timezone_offset"] || 0,
        need_login: true
      )
      |> push_event("restore", %{key: @local_store_key, event: "restoreAuth"})
      |> ok()
    else
      socket
      |> ok()
    end
  end

  @impl true
  def handle_event("login", %{"login" => %{"name" => name}}, socket) do
    me = User.login(name |> String.trim())
    id = User.register(me)

    socket
    |> assign_logged_user(me, id)
    |> push_user_local_store(me)
    |> noreply()
  end

  def handle_event("restoreAuth", nil, socket), do: socket |> noreply()

  def handle_event("restoreAuth", data, socket) do
    {me, rooms} = User.device_decode(data)
    id = User.register(me)

    socket
    |> assign_logged_user(me, id, rooms)
    |> noreply()
  end

  defp assign_logged_user(socket, me, id, rooms \\ []) do
    socket
    |> assign(:me, me)
    |> assign(:my_id, id)
    |> assign(:rooms, rooms)
    |> assign(:need_login, false)
    |> assign(:users, User.list())
  end

  defp push_user_local_store(socket, me, rooms \\ []) do
    socket
    |> push_event("store", %{
      key: @local_store_key,
      data: User.device_encode(me, rooms)
    })
  end
end
