defmodule ChatWeb.MainLive.Page.Feed do
  @moduledoc "Lobby part of chat. User list and room list"
  use ChatWeb, :live_component

  alias Chat.Log
  alias Chat.User

  @items_threshold 100

  def init(socket) do
    {list, till} = load_actions(@items_threshold)

    socket
    |> assign(:action_feed_till, till)
    |> assign(:items, nil)
    |> stream_configure(:action_feed_till,  dom_id: &item_dom_id(&1))
    |> assign_feed_stream(list)
    |> assign(:feed_update_mode, :ignore)
  end

  def render(assigns) do
    ~H"""
    <%= for item <- @action_feed_list do %>
      <.item item={item} tz={@tz} />
    <% end %>
    """
  end

  def more(%{assigns: %{action_feed_till: since}} = socket) do
    {list, till} = load_more(@items_threshold, [], since - 1)

    socket
    |> assign(:action_feed_till, till)
    |> assign_feed_stream(list)
    |> assign(:feed_update_mode, :append)
  end

  def close(socket) do
    socket
    |> assign(:action_feed_till, nil)
    |> clean_feed_items()
    |> assign(:items, nil)
  end

  def item(
        %{
          item: {dom_id, %{who: who, data: data}},
          tz: timezone
        } = assigns
      ) do
    datetime =
      data
      |> elem(0)
      |> DateTime.from_unix!()
      |> DateTime.shift_zone!(timezone)
      |> Timex.format!("{h12}:{0m} {AM}, {D}.{M}.{YYYY}")

    assigns =
      assign(assigns,
        user: User.by_id(who),
        action: data |> Tuple.delete_at(0),
        datetime: datetime,
        dom_id: dom_id
      )

    ~H"""
    <div class="py-1 flex justify-start" id={@dom_id}>
      <div class="border-0 rounded-md bg-white/20 p-2 flex flex-col justify-start">
        <span class="text-white"><%= @user && @user.name %> <.action action={@action} /></span>
        <div class="text-white/70" style="font-size: 10px;"><%= @datetime %></div>
      </div>
    </div>
    """
  end

  def action(%{action: {action, opts}} = assigns) do
    act = Chat.Log.humanize_action(action)
    to = opts[:to]
    room = opts[:room]

    to =
      if to do
        to
        |> User.by_id()
      end

    room =
      if room do
        room
        |> Chat.Rooms.get()
      end

    assigns =
      assign(assigns,
        room: room,
        to: to,
        act: act
      )

    ~H"""
    <%= @act %>

    <%= if @to do %>
      to <%= @to.name %>
    <% end %>

    <%= if @room do %>
      <%= @room.name %>
    <% end %>
    """
  end

  def action(%{action: {action}} = assigns) do
    assigns =
      assign(assigns,
        act: Chat.Log.humanize_action(action)
      )

    ~H"""
    <%= @act %>
    """
  end

  defp load_actions(count) do
    {list, till} = Log.list() |> to_maps()
    list_count = list |> Enum.count()

    if count <= list_count or till < 1 do
      {list, till}
    else
      load_more(count - list_count, list, till - 1)
    end
  end

  defp load_more(count, small_list, since) do
    {list, till} = Log.list(since) |> to_maps()
    list_count = list |> Enum.count()
    rest_count = count - list_count

    if rest_count <= 0 or till < 1 do
      {small_list ++ list, till}
    else
      load_more(rest_count, small_list ++ list, till - 1)
    end
  end

  defp to_maps({list, till}) do
    list
    |> Enum.map(fn {uuid, who, data} ->
      %{id: uuid, who: who, data: data}
    end)
    |> then(& {&1, till})
  end

  defp assign_feed_stream(%{assigns: %{streams: %{action_feed_list: _feed}}} = socket, list) do
    socket
    |> stream_batch_insert(:action_feed_list, list,
      at: -1,
      dom_id: &item_dom_id(&1)
    )
    |> assign_items_uuid(list)
  end

  defp assign_feed_stream(socket, list) do

    socket
    |> stream(:action_feed_list, list)
    |> assign_items_uuid(list)
  end


  defp assign_items_uuid(%{assigns: %{items: nil}} = socket, list) do
    socket |> assign(:items, Enum.map(list, &item_dom_id(&1)))
  end

  defp assign_items_uuid(%{assigns: %{items: items}} = socket, list) do
    socket |> assign(:items, Enum.map(list, &item_dom_id(&1)) ++ items)
  end

  defp clean_feed_items(socket) do
    socket.assigns.items
    |> Enum.reduce(socket, fn item, socket ->
      stream_delete_by_dom_id(socket, :action_feed_list, item)
    end)
  end

  defp item_dom_id(%{id: uuid}), do: "action_feed_list-#{uuid}"
end
