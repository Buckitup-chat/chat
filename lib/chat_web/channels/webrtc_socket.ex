defmodule ChatWeb.WebRTCSocket do
  @moduledoc """
  WebSocket handler for WebRTC peer connections.
  """
  use Phoenix.Socket

  # Channel definitions
  channel "room:*", ChatWeb.WebRTCChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user.
  @impl true
  def connect(params, socket, _connect_info) do
    # You can add authentication logic here if needed
    # For example, verify a token or session
    {:ok, assign(socket, :user_id, params["user_id"] || "anonymous")}
  end

  # Socket IDs are topics that allow you to identify all sockets for a given user:
  @impl true
  def id(socket), do: "webrtc_socket:#{socket.assigns.user_id}"
end
