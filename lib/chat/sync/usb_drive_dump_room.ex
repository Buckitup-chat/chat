defmodule Chat.Sync.UsbDriveDumpRoom do
  @moduledoc """
  Holds state of the current USB drive dump room.
  """

  use GenServer
  use StructAccess

  alias Chat.Identity
  alias Phoenix.PubSub

  @type room_key :: String.t()
  @type room_identity :: %Identity{}
  @type t :: %__MODULE__{}
  @type time :: integer()

  @dump_timeout 60
  @start_timeout 5 * 60

  @dump_topic "chat::usb_drive_dump_room"
  @lobby_topic "chat::lobby"

  defstruct [:identity, :pub_key, :successful?, status: :pending, timer: @start_timeout]

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

  @spec activate(room_key(), room_identity()) :: :ok
  def activate(room_key, room_identity) do
    GenServer.cast(__MODULE__, {:activate, room_key, room_identity})
  end

  @spec dump() :: :ok
  def dump do
    GenServer.cast(__MODULE__, :dump)
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
  def handle_call(:get, _from, dump_room) do
    {:reply, dump_room, dump_room}
  end

  def handle_call(:get_room_key, _from, dump_room) do
    room_key =
      case dump_room do
        %__MODULE__{} = dump_room ->
          dump_room.pub_key

        nil ->
          nil
      end

    {:reply, room_key, dump_room}
  end

  @impl GenServer
  def handle_cast({:activate, room_key, room_identity}, dump_room) do
    dump_room =
      case dump_room do
        %__MODULE__{status: :dumping} = dump_room ->
          dump_room

        _ ->
          Process.send_after(self(), :update_timer, 1000)
          %__MODULE__{identity: room_identity, pub_key: room_key}
      end

    :ok = PubSub.broadcast(Chat.PubSub, @dump_topic, {:update_usb_drive_dump_room, dump_room})

    {:noreply, dump_room}
  end

  def handle_cast(:dump, dump_room) do
    dump_room = %{dump_room | status: :dumping}

    Process.send_after(self(), {:dump_timeout, dump_room.pub_key}, @dump_timeout * 1000)

    :ok = PubSub.broadcast(Chat.PubSub, @dump_topic, {:update_usb_drive_dump_room, dump_room})

    {:noreply, dump_room}
  end

  def handle_cast(:mark_successful, dump_room) do
    dump_room =
      case dump_room do
        %__MODULE__{status: :dumping} = dump_room ->
          %{dump_room | successful?: true}

        dump_room ->
          dump_room
      end

    {:noreply, dump_room}
  end

  def handle_cast(:complete, nil), do: {:noreply, nil}

  def handle_cast(:complete, dump_room) do
    status =
      case dump_room do
        %__MODULE__{successful?: true} ->
          :complete

        _ ->
          :failed
      end

    dump_room = %{dump_room | status: status}

    :ok = PubSub.broadcast(Chat.PubSub, @dump_topic, {:update_usb_drive_dump_room, dump_room})
    :ok = PubSub.broadcast(Chat.PubSub, @lobby_topic, {:new_room, dump_room.pub_key})
    :ok = PubSub.broadcast(Chat.PubSub, @lobby_topic, {:new_user, nil})

    {:noreply, dump_room}
  end

  def handle_cast(:remove, dump_room) do
    dump_room =
      case dump_room do
        %__MODULE__{status: status} when status in [:pending, :complete, :failed] ->
          nil

        dump_room ->
          dump_room
      end

    :ok = PubSub.broadcast(Chat.PubSub, @dump_topic, {:update_usb_drive_dump_room, dump_room})

    {:noreply, dump_room}
  end

  @impl GenServer
  def handle_info(:update_timer, dump_room) do
    dump_room =
      cond do
        is_nil(dump_room) ->
          nil

        dump_room.status != :pending ->
          dump_room

        dump_room.timer - 1 > 0 ->
          Process.send_after(self(), :update_timer, 1000)
          new_timer = dump_room.timer - 1
          %{dump_room | timer: new_timer}

        true ->
          nil
      end

    :ok = PubSub.broadcast(Chat.PubSub, @dump_topic, {:update_usb_drive_dump_room, dump_room})

    {:noreply, dump_room}
  end

  def handle_info({:dump_timeout, room_key}, dump_room) do
    dump_room =
      case dump_room do
        %__MODULE__{pub_key: ^room_key, status: :dumping} ->
          %{dump_room | status: :failed}

        dump_room ->
          dump_room
      end

    :ok = PubSub.broadcast(Chat.PubSub, @dump_topic, {:update_usb_drive_dump_room, dump_room})

    {:noreply, dump_room}
  end
end
