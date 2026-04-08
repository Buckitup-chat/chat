defmodule ChatWeb.WebRTCSocket do
  @moduledoc """
  WebSocket handler for WebRTC peer connections.
  """
  use Phoenix.Socket

  # Channel definitions
  channel "room:*", ChatWeb.WebRTCChannel

  @impl true
  def connect(params, socket, connect_info) do
    peer_ip =
      case connect_info do
        %{peer_data: %{address: ip}} -> ip |> :inet.ntoa() |> to_string()
        _ -> "unknown"
      end

    {:ok, assign(socket, user_id: params["user_id"] || "anonymous", peer_ip: peer_ip)}
  end

  # Socket IDs are topics that allow you to identify all sockets for a given user:
  @impl true
  def id(socket), do: "webrtc_socket:#{socket.assigns.user_id}"
end
