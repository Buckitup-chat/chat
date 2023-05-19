defmodule Chat.Rooms.RoomsBroker do
  @moduledoc "Keeps rooms"
  use GenServer
  import Tools.GenServerHelpers

  alias Chat.Rooms

  def sync do
    GenServer.call(__MODULE__, :sync)
  end

  def list(room_map) do
    GenServer.call(__MODULE__, {:list, room_map})
  end

  def list(room_map, search_term) do
    GenServer.call(__MODULE__, {:list, room_map, search_term})
  end

  def put(room) do
    GenServer.cast(__MODULE__, {:put, room})
  end

  def forget(key) do
    GenServer.cast(__MODULE__, {:forget, key})
  end

  ## Defining GenServer Callbacks

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def init(_) do
    Process.flag(:sensitive, true)

    %{} |> ok_continue(:sync)
  end

  def handle_continue(:sync, _) do
    Rooms.list() |> noreply()
  end

  def handle_call(:sync, _from, _state) do
    Rooms.list() |> reply(:ok)
  end

  def handle_call({:list, room_map}, _from, rooms) do
    filtered =
      rooms
      |> Enum.filter(fn room ->
        room.type in [:public, :request] or Map.has_key?(room_map, room.pub_key)
      end)
      |> Enum.split_with(&Map.has_key?(room_map, &1.pub_key))

    rooms |> reply(filtered)
  end

  def handle_call({:list, room_map, search_term}, _from, rooms) do
    filtered =
      rooms
      |> Enum.filter(fn room ->
        (room.type in [:public, :request] or Map.has_key?(room_map, room.pub_key)) and
          String.match?(room.name, ~r/#{search_term}/i)
      end)
      |> Enum.split_with(&Map.has_key?(room_map, &1.pub_key))

    rooms |> reply(filtered)
  end

  def handle_cast({:put, room}, rooms) do
    [room | rooms]
    |> Enum.uniq_by(& &1.pub_key)
    |> Enum.sort_by(& &1.name)
    |> noreply()
  end

  def handle_cast({:forget, key}, rooms) do
    rooms
    |> Enum.reject(&(&1.pub_key == key))
    |> noreply()
  end
end
