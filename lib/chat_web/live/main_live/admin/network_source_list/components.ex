defmodule ChatWeb.MainLive.Admin.NetworkSourceList.Components do
  @moduledoc """
  Function components of `ChatWeb.MainLive.Admin.NetworkSourceList`: a source card with
  per-status slots, Electric shape badges, inputs and buttons.
  """
  use ChatWeb, :component

  alias Chat.NetworkSynchronization.Status

  attr :id, :integer, required: true
  attr :target, :any, required: true
  attr :status, :any, default: nil
  attr :electric, :map, default: %{}
  slot :inner_block, required: true
  slot :error, required: true
  slot :synchronizing, required: true
  slot :updating, required: true
  slot :cooling, required: true

  def network_source(assigns) do
    ~H"""
    <div id={"network-source-#{@id}"} class="bg-gray-300 border border-gray-400 mt-1 p-1 rounded">
      <%= if is_nil(@status) do %>
        <form phx-change="item-change" phx-target={@target}>
          {render_slot(@inner_block)}
        </form>
      <% else %>
        {then(@status, fn
          %Status.ErrorStatus{} -> render_slot(@error)
          %Status.SynchronizingStatus{} -> render_slot(@synchronizing)
          %Status.UpdatingStatus{} -> render_slot(@updating)
          %Status.CoolingStatus{} -> render_slot(@cooling)
        end)}
      <% end %>
      <.electric_status_row electric={@electric} />
    </div>
    """
  end

  attr :electric, :map, required: true

  def electric_status_row(assigns) do
    ~H"""
    <%= if map_size(@electric) > 0 do %>
      <div class="flex flex-row flex-wrap gap-1 mt-1 border-t border-gray-400 pt-1">
        <%= for {shape, status} <- @electric do %>
          <.electric_shape_badge shape={shape} status={status} />
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :shape, :atom, required: true
  attr :status, :any, required: true

  def electric_shape_badge(assigns) do
    ~H"""
    <span class="text-xs px-1.5 py-0.5 rounded bg-gray-200 flex items-center gap-1">
      <span class="font-mono">{@shape}</span>
      <span class={electric_status_class(@status)}>{electric_status_text(@status)}</span>
    </span>
    """
  end

  slot :inner_block, required: true

  def item_row(assigns) do
    ~H"""
    <div class="flex flex-row items-center">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true

  def item_header(assigns) do
    ~H"""
    <.item_row>
      <div class="grow text-center text-sm font-medium">
        {@title}
      </div>
    </.item_row>
    """
  end

  attr :text, :string, required: true

  def error_message(assigns) do
    ~H"""
    <div class="grow bg-yellow-50 m-1 p-1.5 rounded text-center text-2xl">
      ⚠️&nbsp; {@text}
    </div>
    """
  end

  attr :current, :integer, required: true
  attr :amount, :integer, required: true

  def updating_message(assigns) do
    ~H"""
    <div class="grow text-2xl text-center">
      <progress value={@current} max={@amount}>
        {trunc(100 * @current / max(1, @amount))} %
      </progress>
    </div>
    """
  end

  def sync_message(assigns) do
    ~H"""
    <div class="grow text-lg">Synchronizing...</div>
    """
  end

  def cooling_message(assigns) do
    ~H"""
    <div class="grow text-center text-gray-600">... Cooling down ...</div>
    """
  end

  # Inputs

  attr :id, :integer, required: true
  attr :value, :any, required: true

  def url_input(assigns) do
    ~H"""
    API Url:
    <input
      class="text-sm border-0 rounded bg-gray-200 p-1 m-1 grow"
      type="text"
      name={"item[#{@id}][url]"}
      placeholder="like: https://buckitup.app/naive_api"
      phx-debounce="300"
      value={@value}
    />
    """
  end

  attr :id, :integer, required: true
  attr :value, :any, required: true

  def cooldown_input(assigns) do
    ~H"""
    <div class="grow">
      Cool-down:
      <input
        class="w-[30%] text-right text-sm border-0 rounded bg-gray-200 p-1 m-1"
        type="number"
        min="1"
        name={"item[#{@id}][cooldown_hours]"}
        phx-debounce="300"
        value={@value}
      /> hours
    </div>
    """
  end

  # Buttons

  attr :action, :string, default: "start-sync"
  attr :id, :string, required: true
  attr :target, :any, required: true

  def start_sync_button(assigns) do
    ~H"""
    <button
      class="h-11 px-10 mt-2 text-white border-0 rounded-lg bg-grayscale justify-center grow-0"
      type="button"
      phx-click={@action}
      phx-value-id={@id}
      phx-target={@target}
    >
      Start
    </button>
    """
  end

  attr :action, :string, default: "delete"
  attr :id, :string, required: true
  attr :target, :any, required: true

  def delete_item_button(assigns),
    do: ~H"""
    <button
      class="h-11 px-8 bg-red-500 font-medium border-0 rounded-lg justify-center"
      type="button"
      phx-click={@action}
      phx-value-id={@id}
      phx-target={@target}
    >
      Delete
    </button>
    """

  attr :id, :string, required: true
  attr :target, :any, required: true

  def edit_item_button(assigns) do
    ~H"""
    <button
      class="h-10 px-4 bg-black/20 border-0 rounded-lg justify-center ml-1"
      type="button"
      phx-click="stop-item"
      phx-value-id={@id}
      phx-target={@target}
    >
      Stop
    </button>
    """
  end

  attr :target, :any, required: true
  attr :action, :string, default: "add"

  def add_item_button(assigns),
    do: ~H"""
    <button type="button" phx-click={@action} phx-target={@target}>+ Add</button>
    """

  defp electric_status_text(%Status.LiveStatus{}), do: "✓ live"
  defp electric_status_text(%Status.SynchronizingStatus{}), do: "↻ syncing..."
  defp electric_status_text(%Status.ErrorStatus{reason: r}), do: "✗ err: #{r}"
  defp electric_status_text(_), do: "? unknown"

  defp electric_status_class(%Status.LiveStatus{}), do: "text-green-700"
  defp electric_status_class(%Status.ErrorStatus{}), do: "text-red-700"
  defp electric_status_class(_), do: "text-gray-500"
end
