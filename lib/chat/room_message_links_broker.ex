defmodule Chat.RoomMessageLinksBroker do
  @moduledoc "Keep room links"
  use GenServer
  import Tools.GenServerHelpers

  alias Chat.Rooms.RoomMessageLinks

  def put(hash, data) do
    GenServer.cast(__MODULE__, {:put, hash, data})
  end

  def get(hash) do
    GenServer.call(__MODULE__, {:get, hash})
  end

  def values do
    GenServer.call(__MODULE__, :values)
  end

  def forget(hash) do
    GenServer.cast(__MODULE__, {:forget, hash})
  end

  ## Defining GenServer Callbacks

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def init(_) do
    Process.flag(:sensitive, true)

    %{} |> ok_continue(:sync)
  end

  def handle_continue(:sync, _links) do
    RoomMessageLinks.sync() |> noreply()
  end

  def handle_cast({:put, hash, data}, links) do
    links |> Map.put(hash, data) |> noreply()
  end

  def handle_cast({:forget, hash}, links) do
    links |> Map.drop([hash]) |> noreply()
  end

  def handle_call({:get, hash}, _from, links) do
    data = Map.get(links, hash)
    links |> reply(data)
  end

  def handle_call(:values, _from, links) do
    values = Map.values(links)
    links |> reply(values)
  end
end
