defmodule Chat.Db.FreeSpacesPoller do
  @moduledoc "Sends db status into Phoenix channel"

  use GenServer

  alias Chat.Db.FreeSpaces
  alias Phoenix.PubSub

  @interval :timer.seconds(2)

  def info do
    FreeSpaces.get_all()
  end

  def channel, do: "chat_free_spaces"

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
      {:free_spaces, info()}
    )

    {:noreply, schedule()}
  end

  defp schedule do
    Process.send_after(self(), :tick, @interval)
  end
end
