defmodule ChatWeb.MainLive.Layout.ImageGallery do
  @moduledoc "Image gallery related layout"
  use Phoenix.Component

  def render(assigns) do
    ~H"""
      <%= if @mode == assigns[:gallery][:mode] do %>
        <div id="imageGallery" class="relative bg-black">
          
          <.back_button mode={@mode} />
        
          <div class="h-screen flex justify-center items-center lg:h-[99vh]">
            <img 
              class="w-full z-10 lg:h-[85vh] lg:p-14"
              src={@gallery[:current][:url]}
            />
          </div>

          <div class="button-container flex justify-between absolute bottom-[45%] z-10 w-full p-5" >
            <.prev_button enabled={@gallery[:prev][:url]} mode={@mode}/>
            <.next_button enabled={@gallery[:next][:url]} mode={@mode} />
          </div>

        </div>
      <% end %>
    """
  end

  def back_button(assigns) do
    # JS.add_class("hidden", to: "#imageGallery") |> JS.remove_class("hidden", to: "#dialogInput") |> JS.remove_class("md:hidden", to: "#chatRoomBar") |> JS.remove_class("hidden", to: "#chatContent")
    ~H"""
      <button 
        class="text-white flex relative left-5 top-10"
        phx-click={"#{@mode}/image-gallery/close"}
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="white" viewBox="0 0 24 24">
          <path d="M16.67 0l2.83 2.829-9.339 9.175 9.339 9.167-2.83 2.829-12.17-11.996z"/>
        </svg>
        <p class="left-3.5 bottom-[-3px] absolute">&nbsp;Back</p>  
      </button>
    """
  end

  def prev_button(assigns) do
    ~H"""
      <button 
        class={ @enabled && "" || "hidden"}
        phx-click={"#{@mode}/image-gallery/prev"} 
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="white" viewBox="0 0 24 24">
          <path d="M16.67 0l2.83 2.829-9.339 9.175 9.339 9.167-2.83 2.829-12.17-11.996z"/>
        </svg>
      </button>
    """
  end

  def next_button(assigns) do
    ~H"""
      <button 
        class={ @enabled && "" || "hidden"}
        phx-click={"#{@mode}/image-gallery/next"} 
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="white" viewBox="0 0 24 24">
          <path d="M5 3l3.057-3 11.943 12-11.943 12-3.057-3 9-9z"/>
        </svg>
      </button>
    """
  end
end
