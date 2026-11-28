defmodule ChatWeb.MainLive.Page.Dialog.Messages do
  @moduledoc """
  The dialog message list: loading pages of messages, showing a new message,
  select mode, and forgetting the rendered messages after a change.

  Part of the `ChatWeb.MainLive.Page.Dialog` namespace.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.Dialogs

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

  def show_new(%{assigns: %{me: me, dialog: dialog}} = socket, new_message) do
    messages =
      [Dialogs.read_message(dialog, new_message, me)]
      |> Enum.reject(&is_nil/1)
      |> Chat.Messaging.preload_content()

    socket
    |> assign(:messages, messages)
    |> assign(:message_update_mode, :append)
    |> assign(:page, 0)
    |> push_event("chat:scroll-down", %{})
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
        %{assigns: %{dialog: dialog, me: me, last_load_timestamp: timestamp}} = socket,
        per_page
      ) do
    messages = Dialogs.read(dialog, me, {timestamp, 0}, per_page + 1)
    page_messages = Enum.take(messages, -per_page) |> Chat.Messaging.preload_content()

    socket
    |> assign(:messages, page_messages)
    |> assign(:has_more_messages, length(messages) > per_page)
    |> assign(:last_load_timestamp, set_messages_timestamp(page_messages))
  end

  def forget_current_messages(socket) do
    socket
    |> assign(:messages, [])
    |> assign(:message_update_mode, :append)
  end

  defp set_messages_timestamp([]), do: nil
  defp set_messages_timestamp([message | _]), do: message.index
end
