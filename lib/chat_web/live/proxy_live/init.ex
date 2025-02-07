defmodule ChatWeb.ProxyLive.Init do
  @moduledoc """
  Initial steps

  Steps are run using `run_steps/2`. It uses `Enum.reduce_while/3`, so stops on the first failed step.
  """

  use ChatWeb, :live_view

  alias ChatWeb.ProxyLive.Page
  alias ChatWeb.State.ActorState
  alias ChatWeb.State.RoomMapState

  def run_steps(step_list, socket) do
    Enum.reduce_while(step_list, socket, fn step, socket -> step.(socket) end)
  end

  ################
  # Steps
  ################

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
    |> then(fn actor ->
      {:cont,
       socket
       |> ActorState.set(actor)
       |> RoomMapState.derive()}
    end)
  rescue
    _ -> {:halt, socket |> push_navigate(to: ~p"/")}
  end

  def extract_address(socket, params) do
    case params do
      %{"address" => address} -> {:cont, socket |> set_private(:server, address)}
      _ -> {:halt, socket |> push_navigate(to: ~p"/")}
    end
  end

  def mimic_main_page_mount(socket, session) do
    my_identity = ActorState.my_identity(socket)
    my_pub_key = ActorState.my_pub_key(socket)
    os_name = session |> Map.get("operating_system", "unknown")

    socket
    |> assign(:me, my_identity)
    |> assign(:my_id, my_pub_key |> Base.encode16(case: :lower))
    |> assign(:room_map, RoomMapState.get(socket))
    |> assign(:operating_system, os_name)
    |> assign(:db_status, %{
      flags: [],
      mode: :proxy,
      compacting: false,
      writable: :yes
    })
    |> assign(:media_settings, %Chat.Admin.MediaSettings{})
    |> Page.Lobby.init()
    |> Page.Dialog.init()
    |> then(&{:cont, &1})
  end
end
