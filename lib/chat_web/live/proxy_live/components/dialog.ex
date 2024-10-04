defmodule ChatWeb.ProxyLive.Components.Dialog do
  use ChatWeb, :live_component

  alias ChatWeb.MainLive.Layout

  def mount(socket) do
    socket
    |> assign(:dialog_key, nil)
    |> assign(:messages, [])
    |> stream_configure(:messages, dom_id: &"#{&1.index}-#{&1.id}")
    |> ok()
  end

  def update(new_assigns, socket) do
    new_assigns
    |> case do
      %{server: server, actor: actor, to: to, id: id} ->
        request_last_dialog_messages(server, actor.me, to, id)

        socket
        |> assign(new_assigns |> enrich_actor())
        |> stream(:messages, [], reset: true)

      %{messages: messages} when is_list(messages) ->
        new_assigns
        |> Map.drop([:messages])
        |> then(&(socket |> assign(&1)))
        |> stream(:messages, messages)

      x ->
        socket |> assign(x)
    end
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="bg-white/50">
      <.header card={@to} />
      <.messages messages={@streams[:messages]} me={@actor.me} peer={@to} room_map={@actor_room_map} />
      <.new_message />
    </div>
    """
  end

  defp header(assigns) do
    ~H"""
    <div>
      Dialog with <Layout.Card.hashed_name card={@card} />
    </div>
    """
  end

  defp messages(assigns) do
    ~H"""
    <div>
      <div :if={!@messages}>loading messages ...</div>
      <div :if={@messages} id="dialog-messages" phx-update="stream">
        <div :for={{dom_id, msg} <- @messages} id={dom_id}>
          <Layout.Message.message_block
            chat_type={:dialog}
            me={@me}
            msg={msg}
            peer={@peer}
            room_keys={@room_map |> Map.keys()}
          />
        </div>
      </div>
    </div>
    """
  end

  defp new_message(assigns) do
    ~H"""
    <div>
      new message
    </div>
    """
  end

  def request_last_dialog_messages(server, me, peer, id) do
    component_pid = self()

    Task.start(fn ->
      dialog = Proxy.find_or_create_dialog(server, me, peer)

      messages =
        Proxy.get_dialog_messages(server, dialog)
        |> Enum.map(fn {{:dialog_message, _, index, _}, msg} ->
          {index, msg} |> Chat.Dialogs.DialogMessaging.read(me, dialog)
        end)
        |> Enum.filter(& &1)
        |> Enum.reverse()

      send_update(component_pid, __MODULE__,
        id: id,
        messages: messages,
        dialog: dialog,
        loading: false
      )
    end)

    # ChannelClients.Users.start_link(
    #   uri: "ws://#{server}/proxy-socket/websocket",
    #   on_new_user: fn card ->
    #     send_update(component_pid, __MODULE__, id: id, new_user: card)
    #   end
    # )
  end

  def enrich_actor(assigns) do
    assigns
    |> Map.put(
      :actor_room_map,
      assigns.actor.rooms |> Map.new(fn room -> {Chat.Proto.Identify.pub_key(room), room} end)
    )
  end
end
