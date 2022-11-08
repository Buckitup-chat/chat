defmodule ChatWeb.MainLive.Layout.ImageGallery do
  @moduledoc "Image gallery related layout"
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  def render(assigns) do
    ~H"""
      <%= if @mode == assigns[:gallery][:mode] do %>
        <div id="imageGallery" class="bg-black w-full left-[0%] md:top-[0%] absolute z-30">

          <.back_button mode={@mode} />

          <div class="h-screen flex justify-center items-center lg:h-[99vh]">
            <img
              phx-click={JS.toggle(to: "#backBtn") |> JS.toggle(to: "#prev") |> JS.toggle(to: "#next") }
              class="w-auto z-10 max-h-full lg:px-14"
              src={@gallery[:current][:url]}
            />
          </div>

          <div class="button-container flex justify-between absolute bottom-[45%] w-full p-5" >
            <.prev_button enabled={@gallery[:prev][:url]} mode={@mode}/>
            <.next_button enabled={@gallery[:next][:url]} mode={@mode} />
          </div>

        </div>
      <% end %>
    """
  end

  def back_button(assigns) do
    # JS.add_class("hidden", to: "#imageGallery")
    #  |> JS.remove_class("hidden", to: "#dialogInput")
    #  |> JS.remove_class("md:hidden", to: "#chatRoomBar")
    #  |> JS.remove_class("hidden", to: "#chatContent")
    ~H"""
    <div id="backBtn" class="w-full h-12 backdrop-blur-md bg-white/10 fixed z-20">
      <button
        class="text-white flex z-20"
        phx-click={JS.push("#{@mode}/image-gallery/close") |> JS.remove_class("hidden", to: "#chatContent")}
      >
      <div class="flex pt-2 pl-2">
      <svg class="relative top-1" xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="white" viewBox="0 0 24 24">
          <path d="M16.67 0l2.83 2.829-9.339 9.175 9.339 9.167-2.83 2.829-12.17-11.996z"/>
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
        class={ @enabled && "z-10" || "invisible"}
        phx-click={"#{@mode}/image-gallery/prev"}
      >
        <svg class="a-outline" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="white" viewBox="0 0 24 24">
          <path d="M16.67 0l2.83 2.829-9.339 9.175 9.339 9.167-2.83 2.829-12.17-11.996z"/>
        </svg>

      </button>
    """
  end

  def next_button(assigns) do
    ~H"""
      <button
        id="next"
        class={ @enabled && "z-10" || "invisible"}
        phx-click={"#{@mode}/image-gallery/next"}
      >
        <svg class="a-outline" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="white" viewBox="0 0 24 24">
          <path d="M5 3l3.057-3 11.943 12-11.943 12-3.057-3 9-9z"/>
        </svg>
      </button>
    """
  end
end
