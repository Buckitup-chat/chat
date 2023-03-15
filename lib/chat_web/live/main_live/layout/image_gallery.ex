defmodule ChatWeb.MainLive.Layout.ImageGallery do
  @moduledoc "Image gallery related layout"
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
    <div id={@id} class="hidden bg-black w-full h-full left-[0%] md:top-[0%] absolute z-30">
      <%= if @is_open? do %>
        <.back_button type={@type} target={@myself} />

        <div class="h-screen flex justify-center items-center lg:h-[99vh]">
          <img
            id="galleryImage"
            class="w-auto z-10 max-h-full lg:px-14"
            phx-click={JS.toggle(to: "#backBtn") |> JS.toggle(to: "#prev") |> JS.toggle(to: "#next")}
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
         %{assigns: %{incoming_msg_id: {m_index, m_id} = msg_id, dialog: dialog, me: me}} = socket
       ) do
    dialog
    |> Dialogs.read_message(msg_id, me)
    |> case do
      %{type: :image, content: json} ->
        {id, secret} = json |> StorageId.from_json()

        current = %{
          url:
            Routes.file_url(socket, :image, id |> Base.encode16(case: :lower),
              a: secret |> Base.url_encode64()
            ),
          id: m_id,
          index: m_index
        }

        Enum.each(1..@preloading_range, fn _ ->
          dialog_preload_next()
          dialog_preload_prev()
        end)

        socket
        |> assign(:is_open?, true)
        |> assign(:current, current)
        |> assign(:list, [current])
        |> push_event("gallery:preload", %{to: "preloadedList", url: current.url})

      _ ->
        socket
    end
  end

  defp open(
         %{assigns: %{incoming_msg_id: {m_index, m_id} = msg_id, room_identity: room_identity}} =
           socket
       ) do
    Rooms.read_message(msg_id, room_identity)
    |> case do
      %{type: :image, content: json} ->
        {id, secret} = json |> StorageId.from_json()

        current = %{
          url:
            Routes.file_url(socket, :image, id |> Base.encode16(case: :lower),
              a: secret |> Base.url_encode64()
            ),
          id: m_id,
          index: m_index
        }

        Enum.each(1..@preloading_range, fn _ ->
          room_preload_next()
          room_preload_prev()
        end)

        socket
        |> assign(:is_open?, true)
        |> assign(:current, current)
        |> assign(:list, [current])
        |> push_event("gallery:preload", %{to: "preloadedList", url: current.url})

      _ ->
        socket
    end
  end

  defp preload_next(%{assigns: %{list: []}} = socket), do: socket

  defp preload_next(%{assigns: %{dialog: dialog, next: next, list: list, me: me}} = socket) do
    last = List.last(list)
    msg_id = {last.index, last.id}

    dialog
    |> Dialogs.read_next_message(msg_id, me, fn
      {_, %{type: :image}} -> true
      _ -> false
    end)
    |> case do
      %{content: json, id: id, index: index} ->
        {file_id, secret} = json |> StorageId.from_json()

        last = %{
          url:
            Routes.file_url(socket, :image, file_id |> Base.encode16(case: :lower),
              a: secret |> Base.url_encode64()
            ),
          id: id,
          index: index
        }

        socket
        |> assign(:next, next || last)
        |> assign(:list, list ++ [last])
        |> push_event("gallery:preload", %{to: "preloadedList", url: last.url})

      _ ->
        socket
    end
  end

  defp preload_next(%{assigns: %{room_identity: identity, list: list, next: next}} = socket) do
    last = List.last(list)
    msg_id = {last.index, last.id}

    msg_id
    |> Rooms.read_next_message(identity, fn
      {_, %{type: :image}} -> true
      _ -> false
    end)
    |> case do
      %{content: json, id: id, index: index} ->
        {file_id, secret} = json |> StorageId.from_json()

        last = %{
          url:
            Routes.file_url(socket, :image, file_id |> Base.encode16(case: :lower),
              a: secret |> Base.url_encode64()
            ),
          id: id,
          index: index
        }

        socket
        |> assign(:next, next || last)
        |> assign(:list, list ++ [last])
        |> push_event("gallery:preload", %{to: "preloadedList", url: last.url})

      _ ->
        socket
    end
  end

  defp preload_prev(%{assigns: %{list: []}} = socket), do: socket

  defp preload_prev(%{assigns: %{dialog: dialog, prev: prev, list: list, me: me}} = socket) do
    first = List.first(list)
    msg_id = {first.index, first.id}

    dialog
    |> Dialogs.read_prev_message(msg_id, me, fn
      {_, %{type: :image}} -> true
      _ -> false
    end)
    |> case do
      %{content: json, id: id, index: index} ->
        {file_id, secret} = json |> StorageId.from_json()

        first = %{
          url:
            Routes.file_url(socket, :image, file_id |> Base.encode16(case: :lower),
              a: secret |> Base.url_encode64()
            ),
          id: id,
          index: index
        }

        socket
        |> assign(:prev, prev || first)
        |> assign(:list, [first | list])
        |> push_event("gallery:preload", %{to: "preloadedList", url: first.url})

      _ ->
        socket
    end
  end

  defp preload_prev(%{assigns: %{room_identity: identity, prev: prev, list: list}} = socket) do
    first = List.first(list)
    msg_id = {first.index, first.id}

    msg_id
    |> Rooms.read_prev_message(identity, fn
      {_, %{type: :image}} -> true
      _ -> false
    end)
    |> case do
      %{content: json, id: id, index: index} ->
        {file_id, secret} = json |> StorageId.from_json()

        first = %{
          url:
            Routes.file_url(socket, :image, file_id |> Base.encode16(case: :lower),
              a: secret |> Base.url_encode64()
            ),
          id: id,
          index: index
        }

        socket
        |> assign(:prev, prev || first)
        |> assign(:list, [first | list])
        |> push_event("gallery:preload", %{to: "preloadedList", url: first.url})

      _ ->
        socket
    end
  end

  def switch_next(%{assigns: %{type: type, list: list, current: current, next: next}} = socket) do
    next_index = Enum.find_index(list, fn image -> image == next end)
    double_next = Enum.at(list, next_index + 1, nil)

    case type do
      "dialog" -> dialog_preload_next()
      "room" -> room_preload_next()
    end

    socket
    |> assign(:prev, current)
    |> assign(:current, next)
    |> assign(:next, double_next)
  end

  def switch_prev(%{assigns: %{type: type, list: list, prev: prev, current: current}} = socket) do
    prev_index = Enum.find_index(list, fn image -> image == prev end) || length(list) - 2
    double_prev = Enum.at(list, prev_index - 1, nil)

    case type do
      "dialog" -> dialog_preload_prev()
      "room" -> room_preload_prev()
    end

    socket
    |> assign(:prev, double_prev)
    |> assign(:current, prev)
    |> assign(:next, current)
  end

  defp close(socket) do
    socket
    |> assign(:is_open?, false)
    |> assign(:current, nil)
    |> assign(:prev, nil)
    |> assign(:next, nil)
    |> assign(:list, [])
  end

  defp dialog_preload_next, do: send(self(), {:dialog, {:preload_image_gallery, :next}})
  defp dialog_preload_prev, do: send(self(), {:dialog, {:preload_image_gallery, :prev}})
  defp room_preload_next, do: send(self(), {:room, {:preload_image_gallery, :next}})
  defp room_preload_prev, do: send(self(), {:room, {:preload_image_gallery, :prev}})

  defp is_next_after?(list, current), do: List.last(list) !== current
  defp is_prev_before?([first | _], current), do: first !== current

  def back_button(assigns) do
    ~H"""
    <div id="backBtn" class="w-full h-12 backdrop-blur-md bg-white/10 fixed z-20">
      <button
        class="text-white flex z-20"
        phx-target={@target}
        phx-click={
          JS.push("close")
          |> JS.remove_class("hidden", to: "#chatContent")
          |> JS.add_class("hidden", to: "#imageGallery")
        }
      >
        <div class="flex pt-2 pl-2">
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
