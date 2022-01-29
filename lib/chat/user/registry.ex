defmodule Chat.User.Registry do
  @moduledoc "Registry of User Cards"

  use GenServer
  require Logger

  alias Chat.User.Card
  alias Chat.User.Identity

  ### Interface

  def enlist(%Identity{} = user), do: GenServer.call(__MODULE__, {:enlist, user})

  def all, do: GenServer.call(__MODULE__, :all)

  ### Implementation

  @impl true
  def init(_) do
    {:ok, %{list: %{}}}
  end

  @impl true
  def handle_call(:all, _, %{list: list} = state) do
    {:reply, list, state}
  end

  @impl true
  def handle_call({:enlist, %Identity{} = user}, _, %{list: list}) do
    key = Identity.pub_key(user)

    {:reply, :ok, Map.put(list, key, Card.from_identity(user))}
  end
end
