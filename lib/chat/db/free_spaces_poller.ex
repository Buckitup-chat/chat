defmodule Chat.Db.FreeSpacesPoller do
  @moduledoc "Sends db status into Phoenix channel"

  use GenServer
  require Logger

  alias Chat.Db.FreeSpaces
  alias ChatWeb.MainLive.Page.AdminPanel
  alias Phoenix.PubSub

  @interval :timer.seconds(2)

  def join(admin), do: GenServer.cast(__MODULE__, {:join, admin})

  def leave(admin), do: GenServer.cast(__MODULE__, {:leave, admin})

  def get_info, do: GenServer.call(__MODULE__, :info)

  def info, do: FreeSpaces.get_all()

  def channel, do: "chat_free_spaces"

  #
  # GenServer implementation
  #

  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts |> Enum.into(%{}), name: __MODULE__)
  end

  @impl true
  def init(%{admin: admin}) do
    "#{__MODULE__} has started" |> Logger.info()

    schedule()

    {:ok, %{info: info(), admins: [admin]}}
  end

  @impl true
  def handle_call(:info, _from, %{info: info} = state) do
    {:reply, info, state}
  end

  @impl true
  def handle_cast({:join, admin}, state) do
    {:noreply, %{state | admins: [admin | state.admins]}}
  end

  @impl true
  def handle_cast({:leave, admin}, state) do
    {:noreply, %{state | admins: state.admins |> List.delete(admin)}}
  end

  @impl true
  def handle_info(:tick, state) do
    info = info()

    PubSub.broadcast(
      Chat.PubSub,
      channel(),
      {:free_spaces, info}
    )

    send(self(), :check_close)

    {:noreply, %{state | info: info}}
  end

  @impl true
  def handle_info(:check_close, %{admins: admins} = state) do
    if admins == [] do
      "#{__MODULE__} has stopped" |> Logger.info()

      AdminPanel.stop_poller()
    else
      schedule()
    end

    {:noreply, state}
  end

  defp schedule do
    Process.send_after(self(), :tick, @interval)
  end
end
