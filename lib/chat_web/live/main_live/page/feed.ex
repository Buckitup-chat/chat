defmodule ChatWeb.MainLive.Page.Feed do
  @moduledoc "Lobby part of chat. User list and room list"
  import Phoenix.LiveView, only: [assign: 3]
  import Phoenix.LiveView.Helpers

  alias Chat.Log
  alias Chat.User

  @items_treshold 100

  def init(socket) do
    {list, till} = load_actions(@items_treshold)

    socket
    |> assign(:mode, :action_feed)
    |> assign(:action_feed_till, till)
    |> assign(:action_feed_list, list)
  end

  def more(%{assigns: %{action_feed_till: since}} = socket) do
    {list, till} = load_more(@items_treshold, [], since - 1)

    socket
    |> assign(:action_feed_till, till)
    |> assign(:action_feed_list, list)
  end

  def close(socket) do
    socket
    |> assign(:action_feed_till, nil)
    |> assign(:action_feed_list, nil)
  end

  def item(%{item: {timestamp, who, action}, tz: timezone} = assigns) do
    [date, time] =
      DateTime.from_unix!(timestamp)
      |> DateTime.shift_zone!(timezone)
      |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
      |> String.split(" ")

    user = User.by_id(who)

    ~H"""
      <span style="color: #ccc" title={date}><%= time %></span> &nbsp; <%= user && user.name %> <.action action={action} />
    """
  end

  def action(%{action: {action, opts}} = assigns) do
    act = Chat.Log.humanize_action(action)
    to = opts[:to]
    room = opts[:room]

    to =
      if to do
        to
        |> Chat.Utils.hash()
        |> User.by_id()
      end

    room =
      if room do
        room
        |> Chat.Utils.hash()
        |> Chat.Rooms.get()
      end

    ~H"""
      <%= act %>
      
      <%= if to do %>
        to <%= to.name %>
      <% end %> 

      <%= if room do %>
        <%= room.name %> 
      <% end %>
    """
  end

  def action(%{action: action} = assigns) do
    act = Chat.Log.humanize_action(action)

    ~H"""
      <%= act %>
    """
  end

  defp load_actions(count) do
    {list, till} = Log.list()
    list_count = list |> Enum.count()

    if count <= list_count or till < Log.start_time() do
      {list, till}
    else
      load_more(count - list_count, list, till - 1)
    end
  end

  defp load_more(count, small_list, since) do
    {list, till} = Log.list(since)
    list_count = list |> Enum.count()
    rest_count = count - list_count

    if rest_count <= 0 or till < Log.start_time() do
      {small_list ++ list, till}
    else
      load_more(rest_count, small_list ++ list, till - 1)
    end
  end
end
