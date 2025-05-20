defmodule ChatWeb.WebRTCChannel do
  @moduledoc """
  Channel for WebRTC signaling between peers.
  """
  use Phoenix.Channel
  require Logger

  @impl true
  def join("room:" <> room_id, params, socket) do
    if String.length(room_id) > 0 do
      user_id = params["user_id"] || "user_#{System.unique_integer([:positive, :monotonic])}"

      # Track the user in the process registry if needed
      # Registry.register(Registry.WebRTCPeers, "room:#{room_id}", user_id)

      # Schedule a delayed broadcast to notify other users after the join is complete
      Process.send_after(self(), :notify_join, 100)

      # Return success with the assigned user_id
      {:ok,
       assign(socket, %{
         room_id: room_id,
         user_id: user_id
       })}
    else
      {:error, %{reason: "invalid_room"}}
    end
  end

  @impl true
  def handle_info(:notify_join, %{assigns: %{user_id: user_id}} = socket) do
    # Notify other users in the room after join is complete
    broadcast(socket, "user_joined", %{
      user_id: user_id,
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  @doc """
  Handle incoming signaling messages and forward them to the target peer.
  """
  @impl true
  def handle_in("signal", %{"to" => to, "data" => data} = payload, socket) do
    # Forward the signal to the target peer
    broadcast_from!(socket, "signal", %{
      from: socket.assigns.user_id,
      to: to,
      data: data,
      type: Map.get(payload, "type"),
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  # Handle invalid signal messages
  def handle_in("signal", _payload, socket) do
    Logger.warning("Received invalid signal message")
    {:noreply, socket}
  end

  # Handle ICE candidate exchange
  @impl true
  def handle_in("ice_candidate", %{"candidate" => candidate, "to" => to}, socket) do
    broadcast_from!(socket, "ice_candidate", %{
      from: socket.assigns.user_id,
      to: to,
      candidate: candidate,
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  # Handle offer/answer exchange
  @impl true
  def handle_in("sdp", %{"type" => type, "sdp" => sdp, "to" => to}, socket) do
    broadcast_from!(socket, "sdp", %{
      from: socket.assigns.user_id,
      to: to,
      type: type,
      sdp: sdp,
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  # Handle user leaving the room
  @impl true
  def terminate(reason, socket) do
    # Only broadcast if we have the required assigns
    with %{user_id: user_id} <- socket.assigns,
         %{room_id: _room_id} <- socket.assigns do
      # Broadcast user left event before terminating
      broadcast(socket, "user_left", %{
        user_id: user_id,
        reason: reason
      })
    end

    :ok
  end
end
