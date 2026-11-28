defmodule ChatWeb.MainLive.Admin.NetworkSourceList do
  @moduledoc "List of network sources to sync with"
  use ChatWeb, :live_component

  import ChatWeb.MainLive.Admin.NetworkSourceList.Components

  alias Chat.NetworkSynchronization

  def mount(socket) do
    socket
    |> assign(:list, load_list())
    |> assign(:electric_status, %{})
    |> ok()
  end

  def update(new, socket) do
    case new do
      %{status_update: data} ->
        socket |> assign(:list, merge_new_status(data, socket.assigns[:list] || []))

      %{electric_status_update: {peer_url, shape, status}} ->
        socket.assigns.electric_status
        |> merge_electric_status(peer_url, shape, status)
        |> then(&assign(socket, :electric_status, &1))

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
        <.network_source
          id={item.id}
          target={@myself}
          status={status}
          electric={electric_status_for(item, @electric_status)}
        >
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

  defp electric_status_for(%{url: url}, electric_status) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port} when is_binary(host) ->
        Map.get(electric_status, "#{scheme}://#{host}:#{port}", %{})

      _ ->
        %{}
    end
  end

  defp merge_electric_status(electric_status, peer_url, shape, status) do
    Map.update(electric_status, peer_url, %{shape => status}, &Map.put(&1, shape, status))
  end

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
    case Enum.find_index(list, &(source_id(&1) === id)) do
      nil ->
        NetworkSynchronization.synchronisation()
        |> Enum.filter(&(source_id(&1) == id))
        |> Enum.concat(list)
        |> Enum.sort_by(&source_id/1)

      index ->
        List.update_at(list, index, fn {source, _} -> {source, new_status} end)
    end
  end

  defp source_id({%{id: id}, _}), do: id
end
