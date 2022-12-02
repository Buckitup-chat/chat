defmodule Chat.Db.WriteQueue do
  @moduledoc """
  Ensure data gets in DB before logs, backup and files
  """
  import Chat.Db.WriteQueue.Buffer
  import Tools.GenServerHelpers
  require Record

  Record.defrecord(:q_state, buffer: buffer(), consumer: nil, in_demand: false, mirror: nil)

  use GenServer

  def push(data, server), do: GenServer.cast(server, {:push, data})
  def put(data, server), do: GenServer.cast(server, {:put, data})
  def mark_delete(key, server), do: GenServer.cast(server, {:mark_delete, key})
  def set_mirror(sink, server), do: GenServer.cast(server, {:mirror, sink})

  def put_chunk(chunk, server), do: GenServer.call(server, {:put_chunk, chunk})
  def put_stream(stream, server), do: GenServer.call(server, {:put_stream, stream})

  @doc "This will send data back to pid provided, with genserver cast as {:write, [data]} | {:delete, [:key]}"
  def demand(server), do: GenServer.call(server, :demand)

  #
  #   Implementation
  #

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(_) do
    {:ok, q_state()}
  end

  @impl true
  def handle_call(:demand, {to_pid, _}, state) do
    state
    |> q_state(consumer: to_pid, in_demand: true)
    |> reply_continue(:ok, :produce)
  end

  def handle_call({:put_stream, stream}, _, q_state(buffer: buf) = state) do
    if buffer_has_stream?(buf) do
      state |> reply(:ignored)
    else
      state
      |> q_state(buffer: buffer_stream(buf, stream))
      |> reply_continue(:ok, :produce)
    end
  end

  def handle_call({:put_chunk, chunk}, _, q_state(buffer: buf) = state) do
    if buffer_has_chunk?(buf) do
      state |> reply(:ignored)
    else
      state
      |> q_state(buffer: buffer_chunk(buf, chunk))
      |> reply_continue(:ok, :produce)
    end
  end

  @impl true
  def handle_cast({:push, data}, q_state(buffer: buf) = state) do
    state
    |> q_state(buffer: buffer_add_data(buf, data))
    |> noreply_continue(:produce)
  end

  def handle_cast({:put, data}, q_state(buffer: buf) = state) do
    state
    |> q_state(buffer: buffer_add_log(buf, data))
    |> noreply()
  end

  def handle_cast({:mark_delete, key}, q_state(buffer: buf) = state) do
    state
    |> q_state(buffer: buffer_add_deleted(buf, key))
    |> noreply_continue(:produce)
  end

  def handle_cast({:mirror, sink}, state) do
    state
    |> q_state(mirror: sink)
    |> noreply()
  end

  @impl true
  def handle_continue(:produce, q_state(consumer: nil) = state), do: state |> noreply()
  def handle_continue(:produce, q_state(in_demand: false) = state), do: state |> noreply()

  def handle_continue(:produce, q_state(buffer: buf, consumer: pid, mirror: sink) = state) do
    if Process.alive?(pid) do
      case buffer_yield(buf) do
        {:ignored, _} ->
          state

        {payload, new_buf} ->
          GenServer.cast(pid, payload)
          GenServer.cast(sink, payload)

          state |> q_state(buffer: new_buf)
      end
    else
      state |> q_state(consumer: nil)
    end
    |> noreply()
  end
end
