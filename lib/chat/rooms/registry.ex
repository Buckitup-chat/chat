defmodule Chat.Rooms.Registry do
  @moduledoc "Holds all rooms"
  use GenServer

  alias Chat.Rooms.Room
  alias Chat.Card
  alias Chat.Utils

  ### Interface

  def find(%Card{} = room),
    do: GenServer.call(__MODULE__, {:find, room})

  def all, do: GenServer.call(__MODULE__, :all)

  def update(%Room{} = room), do: GenServer.cast(__MODULE__, {:update, room})

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  ### Implementation

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:find, %Card{pub_key: pub_key}}, _, list) do
    room = Map.get(list, pub_key |> Utils.hash())
    {:reply, room, list}
  end

  @impl true
  def handle_call(:all, _, list), do: {:reply, list, list}

  @impl true
  def handle_cast({:update, %Room{pub_key: pub_key} = room}, list) do
    new_list = Map.put(list, pub_key |> Utils.hash(), room)
    {:noreply, new_list}
  end
end
