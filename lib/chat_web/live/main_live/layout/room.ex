defmodule ChatWeb.MainLive.Layout.Room do
  @moduledoc "Room-related components"
  use ChatWeb, :component

  import ChatWeb.LiveHelpers,
    only: [icon: 1, show_modal: 1, close_content: 1, classes: 1]

  alias Chat.Rooms.Room
  alias ChatWeb.MainLive.Layout
  alias Phoenix.LiveView.JS

  attr :room, Room, required: true, doc: "room struct"
  attr :requests, :list, required: true, doc: "room requests list"
  attr :restrict_actions, :boolean, default: false, doc: "read-only mode indicator"
  attr :linked?, :boolean, default: false, doc: "whether has room the linked messages"
  attr :cargo_room, Room, doc: "cargo room struct"
  attr :cargo_sync, :atom, doc: "cargo sync status"
  attr :media_settings, :map, doc: "admin room media settings"
  attr :usb_drive_dump_room, Room, doc: "dump room"
  attr :usb_drive_dump, :atom, doc: "dump status. :enabled or :disabled"

  def header(assigns) do
    ~H"""
    <div
      id="roomHeader"
      phx-click={JS.dispatch("phx:scroll-to-bottom")}
      class={
        classes(
          "w-full px-8 border-b border-white/10 backdrop-blur-md bg-black/20 z-10 flex flex-row items-center justify-between sticky top-0 right-0"
        )
      }
      style="min-height: 56px;"
    >
      <div class="flex flex-row items-center">
        <button phx-click={JS.push("room/close") |> close_content()} class="sm:hidden pr-3">
          <.icon id="arrowBack" class="w-6 h-6 fill-white" />
        </button>
        <.room_icon type={@room.type} style="fill-white stroke-white " />
        <Layout.Card.hashed_name room={@room} style_spec={:chat_header} />
      </div>
      <%= if @room.type == :public and @linked? do %>
        <.unlink_link restricted={@restrict_actions} />
      <% end %>
      <div class="flex flex-row justify-between">
        <Layout.UsbDriveDumpRoom.button dump={@usb_drive_dump} />
        <Layout.CargoRoom.button cargo_sync={@cargo_sync} />
        <%= if @room.type == :request do %>
          <.request_button requests={@requests} restricted={@restrict_actions} />
        <% end %>
        <.invite_button users={Chat.User.list()} restricted={@restrict_actions} />
      </div>
      <Layout.CargoRoom.bar cargo_room={@cargo_room} media_settings={@media_settings} room={@room} />
      <Layout.UsbDriveDumpRoom.bar dump_room={@usb_drive_dump_room} room={@room} />
    </div>
    """
  end

  attr :type, :atom, required: true, doc: "one of [:public, :private, :request]"
  attr :style, :string, default: "", doc: "style classes"

  def room_icon(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn
        %{type: :public} -> "open"
        %{type: :private} -> "secret"
        %{type: :request} -> "private"
      end)

    ~H"""
    <.icon id={@id} class={"w-4 h-4 stroke-0  #{@style}"} />
    """
  end

  def count_to_backup_message(%{count: 0} = assigns), do: ~H""

  def count_to_backup_message(assigns) do
    assigns =
      assigns
      |> assign_new(:output, fn
        %{count: 1} -> "1 room"
        %{count: count} -> "#{count} rooms"
      end)

    ~H"""
    <p class="mt-3 text-sm text-red-500">
      You have <%= @output %> not backed up. Download the keys to make sure you have access to them after logging out.
    </p>
    """
  end

  def not_found_screen(assigns) do
    ~H"""
    <div id="notFoundScreen">
      <img class="vectorGroup bottomVectorGroup" src="/images/bottom_vector_group.svg" />
      <img class="vectorGroup topVectorGroup" src="/images/top_vector_group.svg" />
      <div class="flex flex-col items-center justify-center h-screen">
        <img class="grayscale w-48 mb-8 " src="/images/logo.png" />
        <span class="text-white text-6xl block"><span>4  0  4</span></span>
        <span class="text-white text-xl">Not found</span>
        <.link
          patch={~p"/"}
          class="mt-5 flex flex-row items-center justify-center border rounded-lg border-white h-11 z-10"
        >
          <.icon id="arrowBack" class="pl-1 mr-1 w-4 h-4 flex fill-white" />
          <span class="mr-1 pr-1 text-sm text-white">Go back to the root</span>
        </.link>
      </div>
    </div>
    """
  end

  defp request_button(assigns) do
    ~H"""
    <button
      class="mr-4 flex items-center"
      phx-click={
        cond do
          @restricted -> show_modal("restrict-write-actions")
          @requests == [] -> nil
          true -> show_modal("room-request-list")
        end
      }
    >
      <.icon id="requestList" class="w-4 h-4 mr-1 z-20 stroke-white fill-white" />
      <span class="text-base text-white">Requests</span>
    </button>
    """
  end

  defp invite_button(assigns) do
    ~H"""
    <button
      class="flex items-center t-invite-btn"
      phx-click={
        cond do
          @restricted -> show_modal("restrict-write-actions")
          @users |> length == 1 -> nil
          true -> show_modal("room-invite-list")
        end
      }
    >
      <.icon id="share" class="w-4 h-4 mr-1 z-20 fill-white" />
      <span class="text-base text-white"> Invite</span>
    </button>
    """
  end

  defp unlink_link(assigns) do
    assigns =
      assigns
      |> assign_new(:link, fn %{restricted: restricted} ->
        if restricted,
          do: show_modal("restrict-write-actions"),
          else: "room/unlink-messages-modal"
      end)

    ~H"""
    <div id="unlinkRoomLink">
      <span class="text-white hidden sm:flex">
        Linked room!<u><a class="text-white" phx-click={@link}> Unlink?</a></u>
      </span>
      <a class="block sm:hidden" phx-click={@link}>
        <.icon id="link" class="w-4 h-4 fill-white stroke-white stroke-2" phx-click={@link} />
      </a>
    </div>
    """
  end
end
