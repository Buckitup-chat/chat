defmodule ChatWeb.MainLive.Page.ImageGallery do
  @moduledoc """
  Image gallery of chats: the LiveComponent (callbacks and markup). Delegates to

  - `ChatWeb.MainLive.Page.ImageGallery.Slides` — opening, preloading, prev/next, closing
  - `ChatWeb.MainLive.Page.ImageGallery.ProxySlide` — opening on a proxy dialog
  - `ChatWeb.MainLive.Page.ImageGallery.Buttons` — back and prev/next controls
  """
  use ChatWeb, :live_component

  import ChatWeb.MainLive.Page.ImageGallery.Buttons

  alias ChatWeb.MainLive.Page.ImageGallery.ProxySlide
  alias ChatWeb.MainLive.Page.ImageGallery.Slides
  alias Phoenix.LiveView.JS

  defdelegate decypher_file_message(message, context), to: ProxySlide

  def mount(socket) do
    socket
    |> assign(:is_open?, false)
    |> assign(:current, nil)
    |> assign(:prev, nil)
    |> assign(:next, nil)
    |> assign(:list, [])
    |> ok()
  end

  def update(new_assigns, socket) do
    {action, new_assigns} = Map.pop(new_assigns, :action)

    socket
    |> assign(new_assigns)
    |> handle_action(action)
    |> ok()
  end

  def handle_event(event, _, socket) do
    case event do
      "switch-next" -> socket |> Slides.switch_next()
      "switch-prev" -> socket |> Slides.switch_prev()
      "close" -> socket |> Slides.close()
    end
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
          <span class="ml-3 text-white truncate">{@current[:id]}</span>
        </div>

        <div class="h-screen flex justify-center items-center lg:h-[99vh]">
          <%= if @current[:url] do %>
            <div
              id="galleryImagePreloader"
              class="w-full h-full flex justify-center items-center hidden text-white/50 text-5xl bg-black"
            >
              loading ...
            </div>
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
              const preloader = document.getElementById('galleryImagePreloader');

              setTimeout(() => {
                if (image.naturalWidth > 0 && image.naturalHeight > 0 && image.complete) {
                  preloader.classList.add('hidden');
                  prevBtn.classList.remove('hidden');
                  nextBtn.classList.remove('hidden');
                  image.classList.remove('hidden');
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
          <.prev_button enabled={prev_before?(@list, @current)} target={@myself} />
          <.next_button enabled={next_after?(@list, @current)} target={@myself} />
        </div>

        <div id="preloadedList" phx-update="ignore"></div>
      <% end %>
    </div>
    """
  end

  defp handle_action(socket, action) do
    case action do
      nil -> socket
      :open -> socket |> Slides.open()
      :preload_next -> socket |> Slides.preload_next()
      :preload_prev -> socket |> Slides.preload_prev()
      :current_delivered -> socket |> Slides.current_slide_delivered()
      # coveralls-ignore-next-line
      _ -> socket
    end
  end

  defp next_after?(list, current), do: List.last(list) !== current
  defp prev_before?([first | _], current), do: first !== current
end
