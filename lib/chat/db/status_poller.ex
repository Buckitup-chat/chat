defmodule Chat.Db.StatusPoller do
  @moduledoc "Sends db status into Phoenix channel"

  use GenServer

  alias Chat.Db.Common
  alias Phoenix.PubSub

  @interval :timer.seconds(1)

  def info do
    [:mode, :flags]
    |> Enum.map(&{&1, Common.get_chat_db_env(&1)})
    |> Enum.into(%{})
    |> Map.put(:compacting, Chat.Db.db() |> CubDB.compacting?())
    |> Map.put(:writable, if(Common.is_dry?(), do: :no, else: :yes))
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
    {:ok, schedule()}
  end

  @impl true
  def handle_info(:tick, _) do
    PubSub.broadcast(
      Chat.PubSub,
      channel(),
      {:db_status, info()}
    )

    {:noreply, schedule()}
  end

  defp schedule do
    Process.send_after(self(), :tick, @interval)
  end
end
