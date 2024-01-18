defmodule ChatWeb.MainLive.Page.ImageGallery do
  @moduledoc "Image gallery of chats"
  use ChatWeb, :live_component
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.Dialogs
  alias Chat.Rooms
  alias Chat.Utils.StorageId

  alias Phoenix.LiveView.JS

  @preloading_range 5

  def mount(socket) do
    socket
    |> assign(:is_open?, false)
    |> assign(:current, nil)
    |> assign(:prev, nil)
    |> assign(:next, nil)
    |> assign(:list, [])
    |> ok()
  end

  def update(%{action: action} = assigns, socket) do
    socket
    |> assign(Map.drop(assigns, [:action]))
    |> handle_action(action)
    |> ok()
  end

  def update(assigns, socket) do
    socket |> assign(assigns) |> ok()
  end

  def handle_event("switch-next", _, socket) do
    socket
    |> switch_next()
    |> noreply()
  end

  def handle_event("switch-prev", _, socket) do
    socket
    |> switch_prev()
    |> noreply()
  end

  def handle_event("close", _, socket) do
    socket
    |> close()
    |> noreply()
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="hidden bg-black w-full h-full left-[0%] md:top-[0%] fixed z-30">
      <%= if @is_open? do %>
        <div
          id="topPanel"
          class="w-full h-12 px-2 backdrop-blur-lg bg-white/10 fixed z-20 flex justify-between items-center"
        >
          <.back_button type={@type} target={@myself} />
          <span class="ml-3 text-white truncate"><%= @current[:id] %></span>
        </div>

        <div class="h-screen flex justify-center items-center lg:h-[99vh]">
          <%= if @current[:url] do %>
            <img
              id="galleryImage"
              class="w-auto z-10 max-h-full lg:px-14"
              phx-click={
                JS.toggle(to: "#topPanel", display: "flex")
                |> JS.toggle(to: "#prev")
                |> JS.toggle(to: "#next")
              }
              src={@current[:url]}
              onload="
            function handleArrows() {
              const prevBtn = document.getElementById('prev');
              const nextBtn = document.getElementById('next');
              const image = document.getElementById('galleryImage');

              setTimeout(() => {
                if (image.naturalWidth > 0 && image.naturalHeight > 0 && image.complete) {
                  prevBtn.classList.remove('hidden');
                  nextBtn.classList.remove('hidden');
                } else {
                  handleArrows();
                }
              }, '300');
            }

            handleArrows();
            "
            />
          <% else %>
            <span class="text-white" phx-mounted={JS.show(to: "#prev") |> JS.show(to: "#next")}>
              The message is lost.
            </span>
          <% end %>
        </div>

        <div class="button-container flex justify-between absolute bottom-[45%] w-full p-5">
          <.prev_button enabled={is_prev_before?(@list, @current)} target={@myself} />
          <.next_button enabled={is_next_after?(@list, @current)} target={@myself} />
        </div>

        <div id="preloadedList" phx-update="ignore"></div>
      <% end %>
    </div>
    """
  end

  defp handle_action(socket, action) do
    case action do
      :open -> socket |> open()
      :preload_next -> socket |> preload_next()
      :preload_prev -> socket |> preload_prev()
      _ -> socket
    end
  end

  defp open(
         %{
           assigns: %{
             incoming_msg_id: msg_id,
             type: :room,
             room_identity: room_identity
           }
         } =
           socket
       ) do
    IO.inspect(socket.assigns, label: "open")

    socket
    |> assign_current(msg_id, Rooms.read_message(msg_id, room_identity))
  end

  defp open(%{assigns: %{incoming_msg_id: msg_id, dialog: dialog, me: me}} = socket) do
    IO.inspect(socket.assigns, label: "open")

    socket
    |> assign_current(msg_id, Dialogs.read_message(dialog, msg_id, me))
  end

  defp preload_prev(%{assigns: %{list: []}} = socket), do: socket

  defp preload_prev(%{assigns: %{room_identity: identity, type: :room, list: list}} = socket) do
    first = List.first(list)

    socket
    |> assign_prev(
      Rooms.read_prev_message({first.index, first.id}, identity, fn
        {_, %{type: :image}} -> true
        _ -> false
      end)
    )
  end

  defp preload_prev(%{assigns: %{dialog: dialog, list: list, me: me}} = socket) do
    first = List.first(list)

    socket
    |> assign_prev(
      Dialogs.read_prev_message(dialog, {first.index, first.id}, me, fn
        {_, %{type: :image}} -> true
        _ -> false
      end)
    )
  end

  defp preload_next(%{assigns: %{list: []}} = socket), do: socket

  defp preload_next(%{assigns: %{room_identity: identity, type: :room, list: list}} = socket) do
    last = List.last(list)

    socket
    |> assign_next(
      Rooms.read_next_message({last.index, last.id}, identity, fn
        {_, %{type: :image}} -> true
        _ -> false
      end)
    )
  end

  defp preload_next(%{assigns: %{dialog: dialog, list: list, me: me}} = socket) do
    last = List.last(list)

    socket
    |> assign_next(
      Dialogs.read_next_message(dialog, {last.index, last.id}, me, fn
        {_, %{type: :image}} -> true
        _ -> false
      end)
    )
  end

  defp switch_prev(%{assigns: %{list: list, prev: prev, current: current}} = socket) do
    prev_index = Enum.find_index(list, fn image -> image == prev end) || length(list) - 2
    double_prev = Enum.at(list, prev_index - 1, nil)

    socket
    |> assign(:prev, double_prev)
    |> assign(:current, prev)
    |> assign(:next, current)
    |> invoke_preload_prev(1)
  end

  defp switch_next(%{assigns: %{list: list, current: current, next: next}} = socket) do
    next_index = Enum.find_index(list, fn image -> image == next end)
    double_next = Enum.at(list, next_index + 1, nil)

    socket
    |> assign(:prev, current)
    |> assign(:current, next)
    |> assign(:next, double_next)
    |> invoke_preload_next(1)
  end

  defp close(socket) do
    socket
    |> assign(:is_open?, false)
    |> assign(:current, nil)
    |> assign(:prev, nil)
    |> assign(:next, nil)
    |> assign(:list, [])
  end

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
    last = %{url: image_url(file_id, secret), id: id, index: index}

    socket
    |> assign(:next, next || last)
    |> assign(:list, list ++ [last])
    |> push_event("gallery:preload", %{to: "preloadedList", url: last.url})
  end

  defp assign_next(socket, nil), do: socket

  defp invoke_preload_prev(%{assigns: %{type: type}} = socket, range \\ @preloading_range) do
    command =
      case type do
        :dialog -> {:dialog, {:preload_image_gallery, :prev}}
        :room -> {:room, {:preload_image_gallery, :prev}}
      end

    Enum.each(1..range, fn _ -> send(self(), command) end)

    socket
  end

  defp invoke_preload_next(%{assigns: %{type: type}} = socket, range \\ @preloading_range) do
    command =
      case type do
        :dialog -> {:dialog, {:preload_image_gallery, :next}}
        :room -> {:room, {:preload_image_gallery, :next}}
      end

    Enum.each(1..range, fn _ -> send(self(), command) end)

    socket
  end

  defp is_next_after?(list, current), do: List.last(list) !== current
  defp is_prev_before?([first | _], current), do: first !== current

  defp image_url(id, secret) do
    key = id |> Base.encode16(case: :lower)
    code = secret |> Base.url_encode64()

    ~p"/get/image/#{key}?a=#{code}"
    |> url()
  end

  def back_button(assigns) do
    ~H"""
    <div id="backBtn" class="items-center">
      <button
        class="text-white flex z-20"
        phx-target={@target}
        phx-click={
          JS.push("close")
          |> JS.remove_class("hidden", to: "#chatContent")
          |> JS.add_class("hidden", to: "#imageGallery")
        }
      >
        <div class="flex pl-2">
          <svg
            class="relative top-1"
            xmlns="http://www.w3.org/2000/svg"
            width="16"
            height="16"
            fill="white"
            viewBox="0 0 24 24"
          >
            <path d="M16.67 0l2.83 2.829-9.339 9.175 9.339 9.167-2.83 2.829-12.17-11.996z" />
          </svg>
          <p>&nbsp;Back</p>
        </div>
      </button>
    </div>
    """
  end

  def prev_button(assigns) do
    ~H"""
    <button
      id="prev"
      class={(@enabled && "z-10") || "invisible"}
      phx-target={@target}
      phx-click={
        JS.push("switch-prev")
        |> JS.add_class("hidden", to: "#prev")
        |> JS.add_class("hidden", to: "#next")
      }
    >
      <svg
        class="a-outline"
        xmlns="http://www.w3.org/2000/svg"
        width="24"
        height="24"
        fill="white"
        viewBox="0 0 24 24"
      >
        <path d="M16.67 0l2.83 2.829-9.339 9.175 9.339 9.167-2.83 2.829-12.17-11.996z" />
      </svg>
    </button>
    """
  end

  def next_button(assigns) do
    ~H"""
    <button
      id="next"
      class={(@enabled && "z-10") || "invisible"}
      phx-click={
        JS.push("switch-next")
        |> JS.add_class("hidden", to: "#next")
        |> JS.add_class("hidden", to: "#prev")
      }
      phx-target={@target}
    >
      <svg
        class="a-outline"
        xmlns="http://www.w3.org/2000/svg"
        width="24"
        height="24"
        fill="white"
        viewBox="0 0 24 24"
      >
        <path d="M5 3l3.057-3 11.943 12-11.943 12-3.057-3 9-9z" />
      </svg>
    </button>
    """
  end
end
