defmodule ChatWeb.MainLive.Admin.NetworkSourceList do
  @moduledoc "List of network sources to sync with"
  use ChatWeb, :live_component

  alias Chat.NetworkSynchronization
  alias Chat.NetworkSynchronization.Status

  def mount(socket) do
    socket
    |> assign(:list, load_list())
    |> ok()
  end

  def update(new, socket) do
    case new do
      %{status_update: data} ->
        socket |> assign(:list, merge_new_status(data, socket.assigns[:list] || []))

      _ ->
        socket |> assign(new)
    end
    |> ok()
  end

  defp render_fresh_list(socket) do
    socket
    |> assign(:list, load_list())
    |> noreply()
  end

  def handle_event("add", _, socket) do
    append_new_to_list()

    socket |> render_fresh_list()
  end

  def handle_event("item-change", params, socket) do
    [{id, fields}] =
      params["item"]
      |> Map.to_list()

    update_list_item(id |> String.to_integer(), fields)
    socket |> render_fresh_list()
  end

  def handle_event("delete", params, socket) do
    params["id"]
    |> String.to_integer()
    |> remove_from_list()

    socket |> render_fresh_list()
  end

  def handle_event("start-sync", params, socket) do
    params["id"]
    |> String.to_integer()
    |> start_source_sync()

    socket |> render_fresh_list()
  end

  def handle_event("stop-item", params, socket) do
    params["id"]
    |> String.to_integer()
    |> stop_source_sync()

    socket |> render_fresh_list()
  end

  def render(assigns) do
    ~H"""
    <div>
      <%= for {item, status} <- @list do %>
        <.network_source id={item.id} target={@myself} status={status}>
          <.item_row>
            <.url_input id={item.id} value={item.url} />
            <.delete_item_button id={item.id} target={@myself} />
          </.item_row>
          <.item_row>
            <.cooldown_input id={item.id} value={item.cooldown_hours} />
            <.start_sync_button id={item.id} target={@myself} />
          </.item_row>

          <:error>
            <.item_header title={item.url} />
            <.item_row>
              <.error_message text={status.reason} />
              <.edit_item_button id={item.id} target={@myself} />
            </.item_row>
          </:error>

          <:synchronizing>
            <.item_header title={item.url} />
            <.item_row>
              <.sync_message />
              <.edit_item_button id={item.id} target={@myself} />
            </.item_row>
          </:synchronizing>

          <:updating>
            <.item_header title={item.url} />
            <.item_row>
              <.updating_message current={status.done} amount={status.total} />
              <.edit_item_button id={item.id} target={@myself} />
            </.item_row>
          </:updating>

          <:cooling>
            <.item_header title={item.url} />
            <.item_row>
              <.cooling_message />
              <.edit_item_button id={item.id} target={@myself} />
            </.item_row>
          </:cooling>
        </.network_source>
      <% end %>
      <.add_item_button target={@myself} />
    </div>
    """
  end

  attr :id, :integer, required: true
  attr :target, :any, required: true
  attr :status, :any, default: nil
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
    </div>
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

  defp load_list, do: NetworkSynchronization.synchronisation()
  defp append_new_to_list, do: NetworkSynchronization.add_source()
  defp remove_from_list(id), do: NetworkSynchronization.remove_source(id)
  defp start_source_sync(id), do: NetworkSynchronization.start_source(id)
  defp stop_source_sync(id), do: NetworkSynchronization.stop_source(id)

  defp update_list_item(id, fields) do
    NetworkSynchronization.update_source(id,
      url: fields["url"],
      cooldown_hours: fields["cooldown_hours"]
    )
  end

  defp merge_new_status({id, new_status}, list) do
    if index = list |> Enum.find_index(&(source_id(&1) === id)) do
      List.update_at(list, index, fn {source, _} -> {source, new_status} end)
    else
      NetworkSynchronization.synchronisation()
      |> Enum.filter(&(source_id(&1) == id))
      |> Enum.concat(list)
      |> Enum.sort_by(&source_id/1)
    end
  end

  defp source_id({%{id: id}, _}), do: id
end
