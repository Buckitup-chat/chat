defmodule ChatWeb.MainLive.Page.Room.Messages do
  @moduledoc """
  The room's message list: paging older messages in, appending new ones, scrolling to a
  linked message, and the select mode toggle. Owns the `:messages`, `:page`,
  `:has_more_messages`, `:last_load_timestamp`, `:last_loaded_index` and
  `:message_update_mode` assigns.

  Part of the `ChatWeb.MainLive.Page.Room` namespace; message changes live in
  `ChatWeb.MainLive.Page.Room.MessageActions`.
  """

  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.Identity
  alias Chat.Rooms
  alias ChatWeb.MainLive.Page.Room.Requests

  @per_page 15

  def load_more_messages(%{assigns: %{page: page}} = socket) do
    socket
    |> assign(:page, page + 1)
    |> assign(:message_update_mode, :prepend)
    |> assign_messages()
    |> case do
      %{assigns: %{input_mode: :select}} = socket ->
        socket
        |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      socket ->
        socket
    end
  end

  def load_new_messages(
        %{
          assigns: %{
            room: room,
            room_identity: identity,
            last_loaded_index: index
          }
        } = socket
      )
      when not is_nil(room) and not is_nil(identity) do
    socket
    |> assign(:message_update_mode, :append)
    |> assign(
      :messages,
      if(index,
        do: Rooms.read_to(room, identity, {nil, 0}, {index + 1, 0}),
        else: Rooms.read(room, identity, {nil, 0}, @per_page + 1)
      )
      |> Chat.Messaging.preload_content()
    )
    |> assign_last_loaded_index()
    |> push_event("chat:scroll-down", %{})
    |> case do
      %{assigns: %{input_mode: :select}} = socket ->
        socket
        |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      socket ->
        socket
    end
  end

  def load_new_messages(socket), do: socket

  def show_new(
        %{assigns: %{room_identity: %Identity{} = identity}} = socket,
        {index, new_message}
      ) do
    verified_message = Rooms.read_message({index, new_message}, identity)

    if verified_message do
      socket
      |> assign(:page, 0)
      |> assign(:messages, [verified_message] |> Chat.Messaging.preload_content())
      |> assign(:message_update_mode, :append)
      |> Requests.maybe_update_requests(verified_message)
      |> push_event("chat:scroll-down", %{})
    else
      socket
    end
  end

  def show_new(socket, new_message) do
    identity = socket.assigns[:room_identity] |> inspect()
    message = new_message |> inspect()
    Logger.warning(["Cannot show new message in room. ", "msg: ", message, " room: ", identity])

    socket
  end

  def toggle_messages_select(%{assigns: %{}} = socket, %{"action" => "on"}) do
    socket
    |> forget_current_messages()
    |> assign(:input_mode, :select)
    |> push_event("chat:toggle", %{to: "#chat-messages", class: "selectMode"})
  end

  def toggle_messages_select(%{assigns: %{input_mode: :select}} = socket, %{"action" => "off"}) do
    socket
    |> forget_current_messages()
    |> assign(:input_mode, :plain)
  end

  def assign_messages(socket, per_page \\ @per_page)

  def assign_messages(%{assigns: %{has_more_messages: false}} = socket, _), do: socket

  def assign_messages(
        %{
          assigns: %{
            room: room,
            room_identity: identity,
            last_load_timestamp: index
          }
        } = socket,
        per_page
      ) do
    messages = Rooms.read(room, identity, {index, 0}, per_page + 1)
    page_messages = Enum.take(messages, -per_page) |> Chat.Messaging.preload_content()

    socket
    |> assign(:messages, page_messages)
    |> assign(:has_more_messages, length(messages) > per_page)
    |> assign(:last_load_timestamp, set_messages_timestamp(page_messages))
  end

  def assign_last_loaded_index(%{assigns: %{messages: messages}} = socket) do
    socket
    |> assign(
      :last_loaded_index,
      List.last(messages)
      |> then(&(get_in(&1, [Access.key!(:index)]) || socket.assigns[:last_loaded_index] || 0))
    )
  end

  def load_messages_to(%{assigns: %{has_more_messages: false}} = socket, {_, msg_id}) do
    socket
    |> push_event("chat:scroll", %{to: "#message-block-#{msg_id}"})
    |> push_event("chat:toggle", %{to: "#message-block-#{msg_id}", class: "bg-black/10"})
  end

  def load_messages_to(
        %{
          assigns: %{
            room: room,
            room_identity: identity,
            last_load_timestamp: index,
            messages: messages
          }
        } = socket,
        {msg_index, msg_id}
      ) do
    prev_messages =
      Rooms.read_to(room, identity, {index - 1, 0}, {msg_index, msg_id})
      |> Chat.Messaging.preload_content()

    messages = prev_messages ++ messages

    socket
    |> assign(:messages, messages)
    |> assign(:last_load_timestamp, set_messages_timestamp(messages))
    |> push_event("chat:scroll", %{to: "#message-block-#{msg_id}"})
    |> push_event("chat:toggle", %{to: "#message-block-#{msg_id}", class: "bg-black/10"})
  end

  def forget_current_messages(socket) do
    socket
    |> assign(:messages, [])
    |> assign(:message_update_mode, :append)
  end

  defp set_messages_timestamp([]), do: nil
  defp set_messages_timestamp([message | _]), do: message.index
end
