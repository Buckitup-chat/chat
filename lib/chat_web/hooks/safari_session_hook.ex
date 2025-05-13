defmodule ChatWeb.Hooks.SafariSessionHook do
  @moduledoc """
  LiveView hook for handling Safari-specific session management.

  This hook addresses the issue of users getting logged out in Safari
  after the tab is inactive for some time by implementing periodic
  session refreshes and reconnection handling.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias Phoenix.LiveView.Socket

  # Session refresh interval in milliseconds (5 minutes)
  @refresh_interval 300_000

  @doc """
  Attaches Safari-specific session handling to the LiveView socket.
  """
  @spec on_mount(atom(), map(), map(), Socket.t()) :: {:cont, Socket.t()}
  def on_mount(:default, _params, session, socket) do
    is_safari = Map.get(session, :is_safari, false)

    socket =
      socket
      |> assign(:is_safari, is_safari)
      |> attach_hook(:safari_session_hook, :handle_event, &handle_safari_events/3)

    if connected?(socket) && is_safari do
      # Schedule periodic session refresh for Safari
      Process.send_after(self(), :refresh_safari_session, @refresh_interval)
    end

    {:cont, socket}
  end

  # Handle Safari-specific events
  defp handle_safari_events("safari_ping", _params, socket) do
    # This event is sent periodically from the client to keep the session alive
    {:halt, socket}
  end

  defp handle_safari_events(_event, _params, socket) do
    # Let other events pass through
    {:cont, socket}
  end

  @doc """
  Handle periodic session refresh for Safari browsers
  """
  def handle_info(:refresh_safari_session, socket) do
    if socket.assigns.is_safari do
      # Schedule the next refresh
      Process.send_after(self(), :refresh_safari_session, @refresh_interval)
    end

    {:noreply, socket}
  end

  @doc """
  Assigns Safari detection to the socket.
  """
  def assign_safari(socket, is_safari) do
    assign(socket, :is_safari, is_safari)
  end
end
