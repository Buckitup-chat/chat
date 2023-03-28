defmodule Chat.Sync.CargoRoom do
  @moduledoc """
  Holds pub key of the last cargo room created to facilitate cargo sync.
  """

  use GenServer

  @type room_pub_key :: String.t()

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl GenServer
  def init(:ok) do
    {:ok, nil}
  end

  @spec set(room_pub_key()) :: :ok
  def set(room_pub_key) do
    GenServer.cast(__MODULE__, {:set, room_pub_key})
  end

  @spec get() :: room_pub_key()
  def get do
    GenServer.call(__MODULE__, :get)
  end

  @impl GenServer
  def handle_call(:get, _from, room_pub_key) do
    {:reply, room_pub_key, room_pub_key}
  end

  @impl GenServer
  def handle_cast({:set, room_pub_key}, _room_pub_key) do
    {:noreply, room_pub_key}
  end
end
