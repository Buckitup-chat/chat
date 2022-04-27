defmodule ChatWeb.MainLive.Page.AcceptPeerHandshake do
  @moduledoc "Peer handshake accepting page"
  import Phoenix.LiveView, only: [assign: 3]

  alias Chat.Broker
  alias Chat.Log
  alias Chat.User
  alias Chat.Utils

  def init(%{assigns: %{}} = socket, key) do
    socket
    |> assign(:key, key)
    |> assign(:is_ready?, false)
  end

  def show(%{assigns: %{me: me, key: key}} = socket) do
    case Broker.get(key) do
      {pid, encrypted} -> :ok
      _ -> :time_to_refresh
    end

    socket
    |> assign(:is_ready?, true)
    |> assign(:is_good_key?, false)
  end

  def accept(socket) do
    socket
  end
end
