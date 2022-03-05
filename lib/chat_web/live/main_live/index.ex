defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Chat.Rooms
  alias ChatWeb.MainLive.Page

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
        max_size: 60_000_000,
        progress: &handle_progress/3
      )
      |> allow_upload(:room_image,
        accept: ~w(.jpg .jpeg .png),
        auto_upload: true,
        max_entries: 1,
        max_size: 60_000_000,
        progress: &handle_progress/3
      )
      |> Page.Login.check_stored()
      |> ok()
    else
      socket
      |> ok()
    end
  end

  @impl true
  def handle_event("login", %{"login" => %{"name" => name}}, socket) do
    socket
    |> Page.Login.create_user(name)
    |> Page.Lobby.init()
    |> noreply()
  end

  def handle_event("restoreAuth", nil, socket), do: socket |> noreply()

  def handle_event("restoreAuth", data, socket) do
    socket
    |> Page.Login.load_user(data)
    |> Page.Lobby.init()
    |> noreply()
  end

  def handle_event("open-dialog", %{"user-id" => user_id}, socket) do
    socket
    |> Page.Lobby.close()
    |> Page.Dialog.init(user_id)
    |> noreply()
  end

  def handle_event("dialog-message", %{"dialog" => %{"text" => text}}, socket) do
    socket
    |> Page.Dialog.send_text(text)
    |> noreply()
  end

  def handle_event("dialog-image-change", _, socket), do: socket |> noreply()

  def handle_event("dialog-image-submit", _, socket), do: socket |> noreply()

  def handle_event("close-dialog", _, socket) do
    socket
    |> Page.Dialog.close()
    |> Page.Lobby.init()
    |> noreply()
  end

  def handle_event("create-room", %{"new_room" => %{"name" => name}}, socket) do
    socket
    |> Page.Lobby.new_room(name)
    |> noreply()
  end

  def handle_event("open-room", %{"room" => hash}, socket) do
    socket
    |> Page.Lobby.close()
    |> Page.Room.init(hash)
    |> noreply()
  end

  def handle_event("request-room", %{"room" => hash}, socket) do
    socket
    |> Page.Lobby.request_room(hash)
    |> noreply()
  end

  def handle_event("room-message", %{"room" => %{"text" => text}}, socket) do
    socket
    |> Page.Room.send_text(text)
    |> noreply()
  end

  def handle_event("room-image-submit", _, socket), do: socket |> noreply()

  def handle_event("close-room", _, socket) do
    socket
    |> Page.Room.close()
    |> Page.Lobby.init()
    |> noreply()
  end

  @impl true
  def handle_info({:new_dialog_message, glimpse}, socket) do
    socket
    |> Page.Dialog.show_new(glimpse)
    |> noreply()
  end

  def handle_info({:new_user, card}, socket) do
    socket
    |> Page.Lobby.show_new_user(card)
    |> noreply()
  end

  def handle_info({:new_room, card}, socket) do
    socket
    |> Page.Lobby.show_new_room(card)
    |> noreply()
  end

  def handle_info({:new_room_message, glimpse}, socket) do
    socket
    |> Page.Room.show_new(glimpse)
    |> noreply()
  end

  def handle_info(:room_request, socket) do
    socket
    |> Page.Lobby.approve_requests()
    |> noreply()
  end

  def handle_info(:room_request_approved, socket) do
    socket
    |> Page.Lobby.join_rooms()
    |> noreply()
  end

  def handle_progress(:image, %{done?: true}, socket) do
    socket
    |> Page.Dialog.send_image()
    |> noreply()
  end

  def handle_progress(:image, _, socket), do: socket |> noreply()

  def handle_progress(:room_image, %{done?: true}, socket) do
    socket
    |> Page.Room.send_image()
    |> noreply()
  end

  def handle_progress(:room_image, _, socket), do: socket |> noreply()

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
          phx-click={JS.dispatch("chat:toggle", detail: %{class: "preview"})}
        />
    """
  end

  defp room_message(%{msg: %{type: :text, author_hash: hash}, my_id: my_id} = assigns) do
    %{name: name} = Chat.User.by_id(hash)

    ~H"""
        <span title={@msg.timestamp |> DateTime.from_unix!()}>
        <%= unless hash == my_id do %>
          <i><%= name %></i>:
        <% end %>
        <%= @msg.content %>
        </span>
    """
  end

  defp room_message(
         %{msg: %{type: :image, content: json, author_hash: hash}, my_id: my_id} = assigns
       ) do
    [{id, secret}] =
      json
      |> Jason.decode!()
      |> Map.to_list()

    %{name: name} = Chat.User.by_id(hash)

    assigns =
      assigns
      |> Map.put(:url, "/get/image/#{id}?a=#{secret}")

    ~H"""
        <%= unless hash == my_id do %>
          <i><%= name %></i>:
        <% end %>
        <img 
          title={@msg.timestamp |> DateTime.from_unix!()}
          class="preview"
          src={@url}
          phx-click={JS.dispatch("chat:toggle", detail: %{class: "preview"})}
        />
    """
  end
end
