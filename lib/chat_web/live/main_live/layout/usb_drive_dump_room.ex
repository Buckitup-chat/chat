defmodule ChatWeb.MainLive.Layout.UsbDriveDumpRoom do
  @moduledoc "USB drive dump room related components"

  use ChatWeb, :component

  alias Chat.Sync.UsbDriveDumpRoom

  def bar(assigns) do
    ~H"""
    <%= if @dump_room && @dump_room.pub_key == @room.pub_key do %>
      <div class="w-full px-8 py-4 border-b border-white/10 backdrop-blur-md bg-grayscale/40 z-10 flex flex-row items-center justify-between text-md text-white">
        <div class="flex flex-row items-center text-base">
          USB drive dump activated <.remove_button status={@dump_room.status} />
        </div>

        <.status dump_room={@dump_room} />
      </div>
    <% end %>
    """
  end

  defp status(%{dump_room: %UsbDriveDumpRoom{status: :pending}} = assigns) do
    ~H"""
    <div class="flex text-red-400">
      <div>
        Insert empty USB drive
      </div>

      <.timer timer={@dump_room.timer} />
    </div>
    """
  end

  defp status(%{dump_room: %UsbDriveDumpRoom{status: :dumping}} = assigns) do
    ~H"""
    <div class="flex text-yellow-400">
      Dumping...
    </div>
    """
  end

  defp status(%{dump_room: %UsbDriveDumpRoom{status: :complete}} = assigns) do
    ~H"""
    <div class="relative flex text-green-500 items-center">
      <.icon id="alert" class="peer mr-1 w-4 h-4 fill-white" />

      <div class="absolute top-0 left-0 mt-6 -ml-64 px-4 py-4 w-96 invisible peer-hover:visible rounded-lg bg-black text-white text-center text-xs">
        The sync is complete, unmount the USB drive now.
      </div>

      <div>
        Complete!
      </div>
    </div>
    """
  end

  defp status(%{dump_room: %UsbDriveDumpRoom{status: :failed}} = assigns) do
    ~H"""
    <div class="flex text-red-500">
      Failed!
    </div>
    """
  end

  defp timer(%{timer: timer} = assigns) do
    minutes = "#{div(timer, 60)}"

    seconds =
      timer
      |> rem(60)
      |> formatted_seconds()

    timer = minutes <> ":" <> seconds

    assigns = assign(assigns, :timer, timer)

    ~H"""
    <div class="w-10 ml-1 text-white/90"><%= @timer %></div>
    """
  end

  defp formatted_seconds(seconds) when seconds < 10, do: "0#{seconds}"
  defp formatted_seconds(seconds), do: "#{seconds}"

  defp remove_button(%{status: status} = assigns) when status in [:pending, :complete, :failed] do
    ~H"""
    <div class="cursor-pointer ml-1 rounded-full t-dump-remove" phx-click="dump:remove">
      <.icon id="close" class="w-6 h-6 fill-red-500" />
    </div>
    """
  end

  defp remove_button(assigns) do
    ~H"""

    """
  end

  attr(:dump, :atom, doc: "either one of: :disabled, :enabled, :duplicate_name")

  def button(%{dump: :enabled} = assigns) do
    ~H"""
    <div
      class="mr-2 flex items-center text-base text-white cursor-pointer t-dump-activate"
      phx-click="dump:activate"
    >
      <.icon id="usbDrive" class="w-6 h-6 fill-white" />
      <span>Dump</span>
    </div>
    """
  end

  def button(assigns) do
    ~H"""

    """
  end
end
