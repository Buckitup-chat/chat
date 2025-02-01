defmodule Proxy.SocketClient.ChannelClient do
  @moduledoc """
  A socket client for connecting to that other Phoenix server

  Periodically sends pings and asks the other server for its metrics.
  """
  use Slipstream, restart: :temporary
  import Tools.GenServerHelpers, only: [ok: 1, noreply: 1]

  require Logger

  @topic "remote::chat::lobby"

  def start_link(args) do
    Slipstream.start_link(__MODULE__, args)
  end

  @impl Slipstream
  def init(opts) do
    uri = Keyword.fetch!(opts, :uri)

    callback_map =
      [
        :on_new_user,
        :on_new_dialog_message,
        :on_room_requested,
        :on_room_approved
      ]
      |> Map.new(&{&1, Keyword.fetch!(opts, &1)})

    connect!(uri: uri)
    |> assign(callback_map)
    |> ok()
  end

  @impl Slipstream
  def handle_connect(socket), do: socket |> join(@topic) |> ok()

  @impl Slipstream
  def handle_join(_topic, _join_response, socket), do: socket |> ok()

  @impl Slipstream
  def handle_message(topic, event, {:binary, data}, socket) do
    args = data |> Proxy.Serialize.deserialize_with_atoms()
    ["client handle message", topic, event, args] |> dbg() |> inspect() |> Logger.error()

    # case {topic, event} do
    #   {@topic, "new_user"} ->
    #     socket.assigns.on_new_user.(args)
    #
    #   {@topic, "room_request"} ->
    #     socket.assigns.on_room_requested.(args)
    #
    #   {"remote::chat::user_room_approval:" <> hex_user_key, "room_request_approved"} ->
    #     [hex_user_key, args] |> dbg() |> inspect() |> Logger.error()
    #
    #   # user_key = Base.decode16!(hex_user_key, case: :lower)
    #   # socket.assigns.on_room_approved.({user_key, args})
    #
    #   {"remote::dialog:" <> hex_dialog_key, "new_dialog_message"} ->
    #     dialog_key = Base.decode16!(hex_dialog_key, case: :lower)
    #     socket.assigns.on_new_dialog_message.({dialog_key, args})
    #
    #   {_, _} ->
    #     Logger.error(
    #       "Was not expecting a push (binary) from the server. Heard: " <>
    #         inspect({topic, event, args})
    #     )
    # end

    socket |> ok()
  end

  @impl Slipstream
  def handle_message(@topic, event, message, socket) do
    Logger.error(
      "Was not expecting a push from the server. Heard: " <>
        inspect({@topic, event, message})
    )

    socket |> ok()
  end

  @impl Slipstream
  def handle_info(msg, socket) do
    case msg do
      {:join, topic} ->
        join(socket, "remote::#{topic}")

      {:leave, topic} ->
        leave(socket, "remote::#{topic}")

      x ->
        ["channel_clients", x] |> dbg() |> inspect() |> Logger.error()
        socket
    end
    |> noreply()
  end

  @impl Slipstream
  def handle_disconnect(_reason, socket) do
    {:stop, :normal, socket}
  end
end
