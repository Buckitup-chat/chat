defmodule ChatWeb.ProxyLive.Init do
  use ChatWeb, :live_view
  @moduledoc "Initial steps"

  def check_connected(socket) do
    if connected?(socket),
      do: {:cont, socket},
      else: {:halt, socket}
  end

  def extract_actor(socket) do
    socket
    |> Phoenix.LiveView.get_connect_params()
    |> get_in(["storage", "auth"])
    |> Chat.Actor.from_json()
    |> then(fn actor -> {:cont, socket |> assign(:actor, %Chat.Actor{} = actor)} end)
  rescue
    _ -> {:halt, socket |> push_navigate(to: ~p"/")}
  end

  def extract_address(socket, params) do
    case params do
      %{"address" => address} -> {:cont, socket |> assign(:server, address)}
      _ -> {:halt, socket |> push_navigate(to: ~p"/")}
    end
  end
end
