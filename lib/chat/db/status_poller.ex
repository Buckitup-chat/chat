defmodule Chat.Db.StatusPoller do
  @moduledoc "Sends db status into Phoenix channel"

  use GenServer

  alias Chat.Db.Common
  alias Chat.Storage.Default
  alias Chat.Storage.Links
  alias Phoenix.PubSub

  @interval :timer.seconds(1)

  def info do
    db = Chat.Db.db()

    with pid when is_pid(pid) <- Process.whereis(db),
         true <- Process.alive?(pid) do
      :ok
    else
      _ -> Process.sleep(100)
    end

    compacting = db |> CubDB.compacting?()

    %{
      mode: Default.unit().role,
      links: Links.list(),
      flags: Common.get_chat_db_env(:flags),
      compacting: compacting
    }
    |> Map.put(:writable, if(Common.dry?(), do: :no, else: :yes))
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
