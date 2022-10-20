defmodule Chat.Db.StatusPoller do
  @moduledoc "Sends db status into Phoenix channel"

  use GenServer

  alias Chat.Db.Common
  alias Phoenix.PubSub

  @interval :timer.seconds(1)

  def info do
    [:write_budget, :mode, :flags, :writable]
    |> Enum.map(&{&1, Common.get_chat_db_env(&1)})
    |> Enum.into(%{})
    |> Map.put(:compacting, Chat.Db.db() |> CubDB.compacting?())
  end

  def channel, do: "chat_db_status"

  #
  # GenServer implementation
  #

  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    interval = :timer.send_interval(@interval, :tick)
    {:ok, interval}
  end

  @impl true
  def handle_info(:tick, state) do
    PubSub.broadcast(
      Chat.PubSub,
      channel(),
      {:db_status, info()}
    )

    {:noreply, state}
  end
end
