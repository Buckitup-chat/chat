defmodule ChatWeb.MainLive.Layout.CargoRoom do
  @moduledoc "Cargo room related components"

  use ChatWeb, :component

  alias Chat.Sync.CargoRoom

  def bar(assigns) do
    ~H"""
    <%= if @media_settings.functionality == :cargo && @cargo_room && @cargo_room.pub_key == @room.pub_key do %>
      <div class="w-full px-8 py-4 border-b border-white/10 backdrop-blur-md bg-grayscale/40 z-10 flex flex-row items-center justify-between text-md text-white">
        <div class="text-base">
          Cargo sync activated
        </div>

        <.status cargo_room={@cargo_room} />
      </div>
    <% end %>
    """
  end

  defp status(%{cargo_room: %CargoRoom{status: :pending}} = assigns) do
    ~H"""
    <.remove_button />

    <div class="flex text-red-400">
      <div>
        Insert empty USB drive
      </div>

      <.timer timer={@cargo_room.timer} />
    </div>
    """
  end

  defp status(%{cargo_room: %CargoRoom{status: :syncing}} = assigns) do
    ~H"""
    <div class="flex text-yellow-400">
      Syncing...
    </div>
    """
  end

  defp status(%{cargo_room: %CargoRoom{status: :complete}} = assigns) do
    ~H"""
    <.remove_button />

    <div class="flex text-green-500">
      Complete!
    </div>
    """
  end

  defp status(%{cargo_room: %CargoRoom{status: :failed}} = assigns) do
    ~H"""
    <.remove_button />

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

  defp remove_button(assigns) do
    ~H"""
    <div class="cursor-pointer ml-auto mr-2 t-cargo-remove" phx-click="cargo:remove">Close</div>
    """
  end

  attr :cargo_sync, :atom, doc: "either one of: :disabled, :enabled, :duplicate_name"

  def button(%{cargo_sync: :enabled} = assigns) do
    ~H"""
    <div class="mr-2 text-base text-white cursor-pointer t-cargo-activate" phx-click="cargo:activate">
      Cargo sync
    </div>
    """
  end

  def button(%{cargo_sync: :duplicate_name} = assigns) do
    ~H"""
    <div class="mr-2 text-base text-white t-cargo-activate">Cargo sync</div>
    """
  end

  def button(assigns) do
    ~H"""

    """
  end
end
