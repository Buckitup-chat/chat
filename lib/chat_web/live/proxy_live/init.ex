defmodule ChatWeb.ProxyLive.Init do
  use ChatWeb, :live_view

  @moduledoc """
  Initial steps

  Steps are run using `run_steps/2`. It uses `Enum.reduce_while/3`, so stops on the first failed step.
  """
  alias ChatWeb.ProxyLive.Page

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
    |> then(fn actor -> {:cont, socket |> set_private(:actor, %Chat.Actor{} = actor)} end)
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
    actor = socket |> get_private(:actor)
    os_name = session |> Map.get("operating_system", "unknown")

    socket
    |> assign(:me, actor.me)
    |> assign(:my_id, actor.me |> Chat.Proto.Identify.pub_key() |> Base.encode16(case: :lower))
    |> assign(
      :room_map,
      actor.rooms |> Map.new(fn room -> {Chat.Proto.Identify.pub_key(room), room} end)
    )
    |> assign(:operating_system, os_name)
    |> assign(:db_status, %{
      flags: [],
      mode: :proxy,
      compacting: false,
      writable: :yes
    })
    |> Page.Lobby.init()
    |> Page.Dialog.init()
    |> then(&{:cont, &1})
  end
end
