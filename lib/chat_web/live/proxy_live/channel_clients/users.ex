defmodule ChatWeb.ProxyLive.ChannelClients.Users do
  @moduledoc """
  A socket client for connecting to that other Phoenix server

  Periodically sends pings and asks the other server for its metrics.
  """

  use Slipstream,
    restart: :temporary

  require Logger

  @topic "proxy:clients"

  def start_link(args) do
    Slipstream.start_link(__MODULE__, args)
  end

  @impl Slipstream
  def init(uri: uri, on_new_user: new_user_fn, on_new_dialog_message: new_dialog_message_fn) do
    {:ok,
     connect!(uri: uri)
     |> assign(
       on_new_user: new_user_fn,
       on_new_dialog_message: new_dialog_message_fn
     )}
  end

  @impl Slipstream
  def handle_connect(socket) do
    {:ok, join(socket, @topic)}
  end

  @impl Slipstream
  def handle_join(@topic, _join_response, socket) do
    # an asynchronous push with no reply:
    # push(socket, @topic, "hello", %{})
    {:ok, socket}
  end

  @impl Slipstream
  def handle_info(_x, socket) do
    # x |> inspect() |> Logger.error()
    {:noreply, socket}
  end

  @impl Slipstream
  def handle_message(@topic, type, {:binary, data}, socket) do
    args =
      data
      |> Proxy.Serialize.deserialize_with_atoms()

    # [type, args] |> inspect() |> Logger.error()

    case type do
      "new_user" -> socket.assigns.on_new_user.(args)
      "new_dialog_message" -> socket.assigns.on_new_dialog_message.(args)
    end

    {:ok, socket}
  end

  @impl Slipstream
  def handle_message(@topic, event, message, socket) do
    Logger.error(
      "Was not expecting a push from the server. Heard: " <>
        inspect({@topic, event, message})
    )

    {:ok, socket}
  end

  @impl Slipstream
  def handle_disconnect(_reason, socket) do
    {:stop, :normal, socket}
  end
end
