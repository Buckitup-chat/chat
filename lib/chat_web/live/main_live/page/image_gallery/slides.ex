defmodule ChatWeb.MainLive.Page.ImageGallery.Slides do
  @moduledoc """
  Image gallery navigation state: opening on a room or dialog image, preloading the
  neighbouring images, switching prev/next, closing.

  Part of the `ChatWeb.MainLive.Page.ImageGallery` namespace.
  """

  use ChatWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.Dialogs
  alias Chat.Rooms
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Page.ImageGallery.ProxySlide

  @preloading_range 5

  def open(socket) do
    case socket.assigns do
      %{type: :room, incoming_msg_id: msg_id, room_identity: room_identity} ->
        socket |> assign_current(msg_id, Rooms.read_message(msg_id, room_identity))

      %{type: :dialog, incoming_msg_id: msg_id, dialog: dialog, me: me} ->
        socket
        |> assign_current(msg_id, Dialogs.read_message(dialog, msg_id, me))

      %{type: :proxy_dialog} = assigns ->
        socket |> ProxySlide.open(assigns)
    end
  end

  def preload_prev(socket) do
    case socket.assigns do
      %{list: []} ->
        socket

      %{type: :room, room_identity: identity, list: [first | _]} ->
        socket
        |> assign_prev(
          Rooms.read_prev_message(
            {first.index, first.id},
            identity,
            &image_message?/1
          )
        )

      %{type: :dialog, dialog: dialog, list: [first | _], me: me} ->
        socket
        |> assign_prev(
          Dialogs.read_prev_message(
            dialog,
            {first.index, first.id},
            me,
            &image_message?/1
          )
        )
    end
  end

  def preload_next(socket) do
    case socket.assigns do
      %{list: []} ->
        socket

      %{type: :room, room_identity: identity, list: list} ->
        last = List.last(list)

        socket
        |> assign_next(
          Rooms.read_next_message(
            {last.index, last.id},
            identity,
            &image_message?/1
          )
        )

      %{type: :dialog, dialog: dialog, list: list, me: me} ->
        last = List.last(list)

        socket
        |> assign_next(
          Dialogs.read_next_message(
            dialog,
            {last.index, last.id},
            me,
            &image_message?/1
          )
        )
    end
  end

  def switch_prev(%{assigns: %{list: list, prev: prev, current: current}} = socket) do
    prev_index = Enum.find_index(list, fn image -> image == prev end) || length(list) - 2
    double_prev = Enum.at(list, prev_index - 1, nil)

    socket
    |> assign(:prev, double_prev)
    |> assign(:current, prev)
    |> assign(:next, current)
    |> invoke_preload_prev(1)
  end

  def switch_next(%{assigns: %{list: list, current: current, next: next}} = socket) do
    next_index = Enum.find_index(list, fn image -> image == next end)
    double_next = Enum.at(list, next_index + 1, nil)

    socket
    |> assign(:prev, current)
    |> assign(:current, next)
    |> assign(:next, double_next)
    |> invoke_preload_next(1)
  end

  def close(socket) do
    socket
    |> assign(:is_open?, false)
    |> assign(:current, nil)
    |> assign(:prev, nil)
    |> assign(:next, nil)
    |> assign(:list, [])
  end

  def current_slide_delivered(socket) do
    socket
    |> push_event("gallery:preload", %{to: "preloadedList", url: socket.assigns.current.url})
    |> invoke_preload_next()
    |> invoke_preload_prev()
  end

  defp image_message?(message), do: match?({_, %{type: :image}}, message)

  defp assign_current(socket, {m_index, m_id}, nil) do
    current = %{url: nil, id: m_id, index: m_index}

    socket
    |> assign(:is_open?, true)
    |> assign(:current, current)
    |> assign(:list, [current])
    |> invoke_preload_next()
    |> invoke_preload_prev()
  end

  defp assign_current(socket, {m_index, m_id}, %{type: :image, content: json}) do
    {id, secret} = json |> StorageId.from_json()
    current = %{url: image_url(id, secret), id: m_id, index: m_index}

    socket
    |> assign(:is_open?, true)
    |> assign(:current, current)
    |> assign(:list, [current])
    |> push_event("gallery:preload", %{to: "preloadedList", url: current.url})
    |> invoke_preload_next()
    |> invoke_preload_prev()
  end

  defp assign_prev(%{assigns: %{prev: prev, list: list}} = socket, %{
         content: json,
         id: id,
         index: index
       }) do
    {file_id, secret} = json |> StorageId.from_json()
    first = %{url: image_url(file_id, secret), id: id, index: index}

    socket
    |> assign(:prev, prev || first)
    |> assign(:list, [first | list])
    |> push_event("gallery:preload", %{to: "preloadedList", url: first.url})
  end

  defp assign_prev(socket, nil), do: socket

  defp assign_next(%{assigns: %{next: next, list: list}} = socket, %{
         content: json,
         id: id,
         index: index
       }) do
    {file_id, secret} = json |> StorageId.from_json()

    last = %{
      url: unverified_path(socket, ChatWeb.Router, image_url(file_id, secret)),
      id: id,
      index: index
    }

    socket
    |> assign(:next, next || last)
    |> assign(:list, list ++ [last])
    |> push_event("gallery:preload", %{to: "preloadedList", url: last.url})
  end

  defp assign_next(socket, nil), do: socket

  defp invoke_preload_prev(%{assigns: %{type: type}} = socket, range \\ @preloading_range) do
    command =
      case type do
        :proxy_dialog -> {:dialog, {:preload_image_gallery, :prev}}
        :dialog -> {:dialog, {:preload_image_gallery, :prev}}
        :room -> {:room, {:preload_image_gallery, :prev}}
      end

    Enum.each(1..range, fn _ -> send(self(), command) end)

    socket
  end

  defp invoke_preload_next(%{assigns: %{type: type}} = socket, range \\ @preloading_range) do
    command =
      case type do
        :proxy_dialog -> {:dialog, {:preload_image_gallery, :next}}
        :dialog -> {:dialog, {:preload_image_gallery, :next}}
        :room -> {:room, {:preload_image_gallery, :next}}
      end

    Enum.each(1..range, fn _ -> send(self(), command) end)

    socket
  end

  defp image_url(id, secret) do
    key = id |> Base.encode16(case: :lower)
    code = secret |> Base.url_encode64()

    ~p"/get/image/#{key}?a=#{code}"
  end
end
