defmodule Chat.User.Registry do
  @moduledoc "Registry of User Cards"

  use GenServer
  require Logger

  alias Chat.User.Card
  alias Chat.User.Identity

  ### Interface

  def enlist(%Identity{} = user), do: GenServer.call(__MODULE__, {:enlist, user})

  def all, do: GenServer.call(__MODULE__, :all)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

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
  def handle_call({:enlist, %Identity{name: name} = user}, _, %{list: list} = state) do
    key = user |> Identity.pub_key()

    case Map.get(list, key) do
      nil ->
        card = Card.from_identity(user)
        new_list = Map.put(list, card.pub_key, card)
        {:reply, card.id, %{state | list: new_list}}

      %Card{name: card_name} = card when name != card_name ->
        new_list = Map.put(list, card.pub_key, %{card | name: name})
        {:reply, card.id, %{state | list: new_list}}

      card ->
        {:reply, card.id, state}
    end
  end
end
