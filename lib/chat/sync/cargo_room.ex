defmodule Chat.Sync.CargoRoom do
  @moduledoc """
  Holds state of the current cargo room.
  """

  use GenServer
  use StructAccess

  alias Chat.Rooms
  alias Chat.Rooms.RoomsBroker
  alias Phoenix.PubSub

  @type room_key :: String.t()
  @type t :: %__MODULE__{}
  @type time :: integer()

  @start_timeout 5 * 60
  @sync_timeout 60 * 60

  @cargo_topic "chat::cargo_room"
  @lobby_topic "chat::lobby"

  defstruct [:pub_key, :successful?, :timer_ref, status: :pending, timer: @start_timeout]

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl GenServer
  def init(:ok) do
    {:ok, nil}
  end

  @spec get() :: t() | nil
  def get do
    GenServer.call(__MODULE__, :get)
  end

  @spec get_room_key() :: room_key() | nil
  def get_room_key do
    GenServer.call(__MODULE__, :get_room_key)
  end

  @spec activate(room_key()) :: :ok
  def activate(room_key) do
    GenServer.cast(__MODULE__, {:activate, room_key})
  end

  @spec sync(room_key()) :: :ok
  def sync(room_key) do
    GenServer.cast(__MODULE__, {:sync, room_key})
  end

  @spec mark_successful() :: :ok
  def mark_successful do
    GenServer.cast(__MODULE__, :mark_successful)
  end

  @spec complete() :: :ok
  def complete do
    GenServer.cast(__MODULE__, :complete)
  end

  @spec remove() :: :ok
  def remove do
    GenServer.cast(__MODULE__, :remove)
  end

  @impl GenServer
  def handle_call(:get, _from, cargo_room) do
    {:reply, cargo_room, cargo_room}
  end

  def handle_call(:get_room_key, _from, state) do
    room_key =
      case state do
        %__MODULE__{} = cargo_room ->
          cargo_room.pub_key

        nil ->
          nil
      end

    {:reply, room_key, state}
  end

  @impl GenServer
  def handle_cast({:activate, room_key}, cargo_room) do
    cargo_room =
      case cargo_room do
        %__MODULE__{status: :syncing} = cargo_room ->
          cargo_room

        _ ->
          if cargo_room[:timer_ref] do
            Process.cancel_timer(cargo_room.timer_ref)
          end

          timer_ref = Process.send_after(self(), :update_timer, 1000)
          %__MODULE__{pub_key: room_key, timer_ref: timer_ref}
      end

    :ok = PubSub.broadcast(Chat.PubSub, @cargo_topic, {:update_cargo_room, cargo_room})

    {:noreply, cargo_room}
  end

  def handle_cast({:sync, room_key}, _cargo_room) do
    cargo_room = %__MODULE__{pub_key: room_key, status: :syncing}

    Process.send_after(self(), {:sync_timeout, room_key}, @sync_timeout * 1000)

    :ok = PubSub.broadcast(Chat.PubSub, @cargo_topic, {:update_cargo_room, cargo_room})

    {:noreply, cargo_room}
  end

  def handle_cast(:mark_successful, cargo_room) do
    cargo_room =
      case cargo_room do
        %__MODULE__{status: :syncing} = cargo_room ->
          %{cargo_room | successful?: true}

        cargo_room ->
          cargo_room
      end

    {:noreply, cargo_room}
  end

  def handle_cast(:complete, nil), do: {:noreply, nil}

  def handle_cast(:complete, cargo_room) do
    status =
      case cargo_room do
        %__MODULE__{successful?: true} ->
          :complete

        _ ->
          :failed
      end

    cargo_room.pub_key
    |> Rooms.get()
    |> RoomsBroker.put()

    cargo_room = %{cargo_room | status: status}

    :ok = PubSub.broadcast(Chat.PubSub, @cargo_topic, {:update_cargo_room, cargo_room})
    :ok = PubSub.broadcast(Chat.PubSub, @lobby_topic, {:new_room, cargo_room.pub_key})
    :ok = PubSub.broadcast(Chat.PubSub, @lobby_topic, {:new_user, nil})

    {:noreply, cargo_room}
  end

  def handle_cast(:remove, _cargo_room) do
    cargo_room = nil

    :ok = PubSub.broadcast(Chat.PubSub, @cargo_topic, {:update_cargo_room, cargo_room})

    {:noreply, cargo_room}
  end

  @impl GenServer
  def handle_info(:update_timer, cargo_room) do
    cargo_room =
      cond do
        is_nil(cargo_room) ->
          nil

        cargo_room.status != :pending ->
          cargo_room

        cargo_room.timer - 1 > 0 ->
          Process.send_after(self(), :update_timer, 1000)
          new_timer = cargo_room.timer - 1
          %{cargo_room | timer: new_timer}

        true ->
          :ok = PubSub.broadcast(Chat.PubSub, @cargo_topic, {:update_cargo_room, nil})
          nil
      end

    {:noreply, cargo_room}
  end

  def handle_info({:sync_timeout, room_key}, cargo_room) do
    cargo_room =
      case cargo_room do
        %__MODULE__{pub_key: ^room_key, status: :syncing} ->
          %{cargo_room | status: :failed}

        cargo_room ->
          cargo_room
      end

    :ok = PubSub.broadcast(Chat.PubSub, @cargo_topic, {:update_cargo_room, cargo_room})

    {:noreply, cargo_room}
  end
end
