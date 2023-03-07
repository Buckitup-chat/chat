defmodule ChatWeb.MainLive.Page.Feed do
  @moduledoc "Lobby part of chat. User list and room list"
  import Phoenix.Component

  alias Chat.Log
  alias Chat.User

  @items_treshold 100

  def init(socket) do
    {list, till} = load_actions(@items_treshold)

    socket
    |> assign(:action_feed_till, till)
    |> assign(:action_feed_list, list)
    |> assign(:feed_update_mode, :ignore)
  end

  def more(%{assigns: %{action_feed_till: since}} = socket) do
    {list, till} = load_more(@items_treshold, [], since - 1)

    socket
    |> assign(:action_feed_till, till)
    |> assign(:action_feed_list, list)
    |> assign(:feed_update_mode, :append)
  end

  def close(socket) do
    socket
    |> assign(:action_feed_till, nil)
    |> assign(:action_feed_list, nil)
  end

  def item(%{item: {who, data}, tz: timezone} = assigns) do
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
        datetime: datetime
      )

    ~H"""
    <div class="border-0 rounded-md bg-white/20 p-2 flex flex-col justify-start">
      <span class="text-white"><%= @user && @user.name %> <.action action={@action} /></span>
      <div class="text-white/70" style="font-size: 10px;"><%= @datetime %></div>
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
    {list, till} = Log.list()
    list_count = list |> Enum.count()

    if count <= list_count or till < 1 do
      {list, till}
    else
      load_more(count - list_count, list, till - 1)
    end
  end

  defp load_more(count, small_list, since) do
    {list, till} = Log.list(since)
    list_count = list |> Enum.count()
    rest_count = count - list_count

    if rest_count <= 0 or till < 1 do
      {small_list ++ list, till}
    else
      load_more(rest_count, small_list ++ list, till - 1)
    end
  end
end
