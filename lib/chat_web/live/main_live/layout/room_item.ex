defmodule ChatWeb.MainLive.Layout.RoomItem do
  @moduledoc "Room item rendering component"
  use ChatWeb, :component
  import ChatWeb.LiveHelpers, only: [icon: 1, open_content: 1, classes: 2]
  
  alias Chat.Rooms
  alias Chat.Rooms.Room
  alias ChatWeb.MainLive.Layout
  alias Phoenix.LiveView.JS
  

  attr :room, :map, required: true, doc: "room sctruct"
  attr :selected_room, Room, doc: "selected room sctruct"
  attr :confirmed?, :boolean, default: false, doc: "is that coonfirmed room?"
  attr :click_event, :string, required: true, doc: "phx-click event for the component"
  attr :my_id, :string, doc: "hash of the current user"
  
  def render(%{confirmed?: true} = assigns) do
    ~H"""
    <!-- Desktop view -->
    <li
      phx-click={@click_event}
      phx-value-room={@room.hash}
      class={classes(
        "hidden sm:flex w-full h-9 flex items-center cursor-pointer hover:bg-stone250",
        %{"bg-stone250" => @selected_room && @room.pub_key == @selected_room.pub_key}
      )}>
      <a>
        <div class="flex flex-row px-2">
          <Layout.Card.hashed_name
            room={@room}
            style_spec={:room_selection}
            selected_room={@selected_room}
          />
        </div>
      </a>
      <.item_icon type={@room.type} />
    </li>

    <!-- Mobile view -->
    <li
      phx-click={JS.push(@click_event) |> open_content()}
      phx-value-room={@room.hash}
      class={classes(
        "sm:hidden w-full h-9 flex items-center cursor-pointer hover:bg-stone250",
        %{"bg-stone250" => @room == @selected_room}
      )}>
      <a>
        <div class="flex flex-row pl-7">
          <Layout.Card.hashed_name room={@room} />
        </div>
      </a>
      <.item_icon type={@room.type} />
    </li>
    """
  end

  def render(assigns) do
    ~H"""
    <%= if Rooms.is_requested_by?(@room.hash, @my_id) do %>
      <li class="w-full h-9 cursor-pointer flex items-center hover:bg-stone250">
        <div class="flex flex-row justify-between px-7 w-full">
          <div class="flex flex-row">
            <Layout.Card.hashed_name room={@room} />
          </div>
          <.icon id="time" class="w-4 h-4 flex fill-black/50" />
        </div>
      </li>
    <% else %>
      <li
        class="w-full h-9 cursor-pointer flex items-center hover:bg-stone250"
        phx-click={@click_event}
        phx-value-room={@room.hash}
      >
      <div class="flex flex-row px-7 w-full">
        <Layout.Card.hashed_name room={@room} />
      </div>
    </li>
  <% end %>
  
    """
  end



  defp item_icon(%{type: :request} = assigns) do

    ~H""" 
    <.icon id="private" class="w-5 h-5 stroke-black" />
    """
  end

  defp item_icon(%{type: :private} = assigns) do
    ~H""" 
    <.icon id="secret" class="w-4 h-4" />
    """
  end

  defp item_icon(%{type: :public} = assigns) do
    ~H""" 
    <.icon id="open" class="w-4 h-4" />
    """
  end 
end

