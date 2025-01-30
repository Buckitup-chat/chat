defmodule ChatWeb.UsersChannel do
  @moduledoc """
  Channel server to authorize clients (Slipstream and (maybe) js)
  """
  use ChatWeb, :channel

  @impl true
  def join(topic, _payload, socket) do
    case topic do
      "remote::" <> _ -> {:ok, socket}
      _ -> {:error, %{reason: "unauthorized"}}
    end

    # if authorized?(payload) do
    #   {:ok, socket}
    # else
    #   {:error, %{reason: "unauthorized"}}
    # end
  end

  # Channels can be used in a request/response fashion
  # by sending replies to requests from the client
  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  # It is also common to receive messages from the client and
  # broadcast to everyone in the current topic (users:lobby).
  @impl true
  def handle_in("shout", payload, socket) do
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  # defp authorized?(_payload) do
  #   true
  # end
end
