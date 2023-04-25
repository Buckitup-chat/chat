defmodule Chat.Sync.UsbDriveDumpRoom do
  @moduledoc """
  Holds state of the current USB drive dump room.
  """

  use GenServer
  use StructAccess

  alias Chat.Identity
  alias Chat.Sync.UsbDriveDumpProgress
  alias Phoenix.PubSub

  @type monotonic_offset :: integer()
  @type room_key :: String.t()
  @type room_identity :: %Identity{}
  @type t :: %__MODULE__{}
  @type time :: integer()

  @dump_timeout 60 * 60
  @start_timeout 5 * 60

  @progress_topic "chat::usb_drive_dump_progress"
  @room_topic "chat::usb_drive_dump_room"

  defstruct [
    :identity,
    :monotonic_offset,
    :pub_key,
    :successful?,
    :timer_ref,
    progress: %UsbDriveDumpProgress{},
    status: :pending,
    timer: @start_timeout
  ]

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

  @spec activate(room_key(), room_identity(), monotonic_offset()) :: :ok
  def activate(room_key, room_identity, monotonic_offset) do
    GenServer.cast(__MODULE__, {:activate, room_key, room_identity, monotonic_offset})
  end

  @spec dump() :: :ok
  def dump do
    GenServer.cast(__MODULE__, :dump)
  end

  @spec set_total(integer(), integer()) :: :ok
  def set_total(files, size) do
    GenServer.cast(__MODULE__, {:set_total, files, size})
  end

  @spec update_progress(integer(), String.t(), integer()) :: :ok
  def update_progress(file_number, filename, size) do
    GenServer.cast(__MODULE__, {:update_progress, file_number, filename, size})
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
  def handle_cast({:activate, room_key, room_identity, monotonic_offset}, dump_room) do
    dump_room =
      case dump_room do
        %__MODULE__{status: :dumping} = dump_room ->
          dump_room

        _ ->
          if dump_room[:timer_ref] do
            Process.cancel_timer(dump_room.timer_ref)
          end

          timer_ref = Process.send_after(self(), :update_timer, 1000)

          %__MODULE__{
            identity: room_identity,
            monotonic_offset: monotonic_offset,
            pub_key: room_key,
            timer_ref: timer_ref
          }
      end

    :ok = PubSub.broadcast(Chat.PubSub, @room_topic, {:update_usb_drive_dump_room, dump_room})

    {:noreply, dump_room}
  end

  def handle_cast(:dump, dump_room) do
    dump_room = %{dump_room | progress: %UsbDriveDumpProgress{}, status: :dumping}

    Process.send_after(self(), {:dump_timeout, dump_room.pub_key}, @dump_timeout * 1000)

    :ok = PubSub.broadcast(Chat.PubSub, @room_topic, {:update_usb_drive_dump_room, dump_room})

    {:noreply, dump_room}
  end

  def handle_cast({:set_total, files, size}, %__MODULE__{status: :dumping} = dump_room) do
    progress = %{dump_room.progress | total_files: files, total_size: size}
    {:noreply, %{dump_room | progress: progress}}
  end

  def handle_cast({:set_total, _files, _size}, dump_room),
    do: {:noreply, dump_room}

  def handle_cast(
        {:update_progress, file_number, filename, size},
        %__MODULE__{progress: %UsbDriveDumpProgress{} = progress, status: :dumping} = dump_room
      ) do
    completed_size = progress.completed_size + size
    percentage = round(completed_size / progress.total_size * 100)

    progress = %{
      progress
      | completed_size: completed_size,
        current_file: file_number,
        current_filename: filename,
        percentage: percentage
    }

    dump_room = %{dump_room | progress: progress}

    :ok =
      PubSub.broadcast(Chat.PubSub, @progress_topic, {:update_usb_drive_dump_progress, dump_room})

    {:noreply, dump_room}
  end

  def handle_cast({:update_progress, _file_number, _filename, _size, _last_chunk?}, dump_room),
    do: {:noreply, dump_room}

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

    :ok = PubSub.broadcast(Chat.PubSub, @room_topic, {:update_usb_drive_dump_room, dump_room})

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

    :ok = PubSub.broadcast(Chat.PubSub, @room_topic, {:update_usb_drive_dump_room, dump_room})

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
          timer_ref = Process.send_after(self(), :update_timer, 1000)
          new_timer = dump_room.timer - 1
          %{dump_room | timer: new_timer, timer_ref: timer_ref}

        true ->
          nil
      end

    :ok =
      PubSub.broadcast(Chat.PubSub, @progress_topic, {:update_usb_drive_dump_progress, dump_room})

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

    :ok = PubSub.broadcast(Chat.PubSub, @room_topic, {:update_usb_drive_dump_room, dump_room})

    {:noreply, dump_room}
  end
end
