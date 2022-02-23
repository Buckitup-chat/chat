defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Phoenix.PubSub

  alias Chat.Dialogs
  alias Chat.Rooms
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
        need_login: true,
        mode: :user_list
      )
      |> allow_upload(:image,
        accept: ~w(.jpg .jpeg .png),
        auto_upload: true,
        max_entries: 1,
        max_size: 16_000_000,
        progress: &handle_progress/3
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
    |> assign_user_list()
    |> assign_room_list()
    |> noreply()
  end

  def handle_event("open-dialog", %{"user-id" => user_id}, %{assigns: %{me: me}} = socket) do
    peer = User.by_id(user_id)
    dialog = Dialogs.find_or_open(me, peer)
    messages = dialog |> Dialogs.read(me)

    PubSub.subscribe(Chat.PubSub, dialog |> dialog_topic())

    socket
    |> assign(:mode, :dialog)
    |> assign(:peer, peer)
    |> assign(:dialog, dialog)
    |> assign(:messages, messages)
    |> assign(:message_update_mode, :replace)
    |> noreply()
  end

  def handle_event(
        "dialog-message",
        %{"dialog" => %{"text" => text}},
        %{assigns: %{dialog: dialog, me: me}} = socket
      ) do
    updated_dialog =
      dialog
      |> Dialogs.add_text(me, text)
      |> tap(&Dialogs.update/1)

    PubSub.broadcast!(
      Chat.PubSub,
      updated_dialog |> dialog_topic(),
      {:new_dialog_message, updated_dialog |> Dialogs.glimpse()}
    )

    socket
    |> assign(:dialog, updated_dialog)
    |> noreply()
  end

  def handle_event("dialog-image-change", _, socket) do
    socket |> noreply()
  end

  def handle_event("dialog-image-submit", _, socket) do
    socket |> noreply()
  end

  def handle_event("close-dialog", _, %{assigns: %{dialog: dialog}} = socket) do
    PubSub.unsubscribe(Chat.PubSub, dialog |> dialog_topic())

    socket
    |> assign(:mode, :user_list)
    |> assign(:dialog, nil)
    |> assign(:messages, nil)
    |> assign(:peer, nil)
    |> assign_user_list()
    |> assign_room_list()
    |> noreply()
  end

  @impl true
  def handle_info({:new_dialog_message, glimpse}, %{assigns: %{me: me}} = socket) do
    socket
    |> assign(:messages, glimpse |> Dialogs.read(me))
    |> assign(:message_update_mode, :append)
    |> noreply()
  end

  def handle_progress(:image, %{done?: true}, %{assigns: %{dialog: dialog, me: me}} = socket) do
    updated_dialog =
      consume_uploaded_entries(
        socket,
        :image,
        fn %{path: path}, entry ->
          data = {File.read!(path), entry.client_type}
          {:ok, Dialogs.add_image(dialog, me, data)}
        end
      )
      |> Enum.at(0)
      |> tap(&Dialogs.update/1)

    PubSub.broadcast!(
      Chat.PubSub,
      updated_dialog |> dialog_topic(),
      {:new_dialog_message, updated_dialog |> Dialogs.glimpse()}
    )

    socket
    |> assign(:dialog, updated_dialog)
    |> noreply()
  end

  def handle_progress(:image, _, socket) do
    socket
    |> noreply()
  end

  defp assign_logged_user(socket, me, id, rooms \\ []) do
    socket
    |> assign(:me, me)
    |> assign(:my_id, id)
    |> assign(:rooms, rooms)
    |> assign(:need_login, false)
    |> assign_user_list()
    |> assign_room_list()
  end

  defp assign_user_list(socket) do
    socket
    |> assign(:users, User.list())
  end

  defp assign_room_list(%{assigns: %{rooms: rooms}} = socket) do
    {joined, new} = Rooms.list(rooms)

    socket
    |> assign(:joined_rooms, joined)
    |> assign(:new_rooms, new)
  end

  defp push_user_local_store(socket, me, rooms \\ []) do
    socket
    |> push_event("store", %{
      key: @local_store_key,
      data: User.device_encode(me, rooms)
    })
  end

  defp dialog_topic(%Dialogs.Dialog{a_key: a_key, b_key: b_key}) do
    [a_key, b_key]
    |> Enum.map(fn key -> key |> User.by_key() |> Map.get(:id) end)
    |> Enum.sort()
    |> Enum.join("---")
    |> then(&"dialog:#{&1}")
  end

  defp message(%{msg: %{type: :text}} = assigns) do
    ~H"""
        <span title={@msg.timestamp |> DateTime.from_unix!()}><%= @msg.content %></span>
    """
  end

  defp message(%{msg: %{type: :image, content: json}} = assigns) do
    [{id, secret}] =
      json
      |> Jason.decode!()
      |> Map.to_list()

    assigns =
      assigns
      |> Map.put(:url, "/get/image/#{id}?a=#{secret}")

    ~H"""
        <img 
          title={@msg.timestamp |> DateTime.from_unix!()}
          class="preview"
          src={@url}
          phx-click={JS.dispatch("img:toggle-preview")}
        />
    """
  end
end
