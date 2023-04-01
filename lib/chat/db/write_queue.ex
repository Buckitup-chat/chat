defmodule Chat.Db.WriteQueue do
  @moduledoc """
  Ensure data gets in DB before logs, backup and files
  """
  import Chat.Db.WriteQueue.Buffer
  import Tools.GenServerHelpers
  require Record

  Record.defrecord(:q_state, buffer: buffer(), consumer: nil, in_demand: false, mirrors: [])

  use GenServer

  def push(data, server), do: GenServer.cast(server, {:push, data})
  def put(data, server), do: GenServer.cast(server, {:put, data})
  def mark_delete(key, server), do: GenServer.cast(server, {:mark_delete, key})

  def set_mirrors(sink, servers) when is_list(servers),
    do: Enum.each(servers, &set_mirrors(sink, &1))

  def set_mirrors(sink, server), do: GenServer.cast(server, {:mirrors, sink})

  def put_chunk(chunk, server), do: GenServer.call(server, {:put_chunk, chunk}, :infinity)
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
    |> produce()
    |> reply(:ok)
  end

  def handle_call({:put_stream, stream}, _, q_state(buffer: buf) = state) do
    if buffer_has_stream?(buf) do
      state |> reply(:ignored)
    else
      state
      |> q_state(buffer: buffer_stream(buf, stream))
      |> produce()
      |> reply(:ok)
    end
  end

  def handle_call({:put_chunk, chunk}, from_pid, q_state(buffer: buf) = state) do
    if buffer_has_chunk?(buf) do
      state
      |> q_state(buffer: buffer_enqueue_chunk(buf, from_pid, chunk)
      |> noreply()
    else
      state
      |> q_state(buffer: buffer_chunk(buf, chunk))
      |> produce()
      |> reply(:ok)
    end
  end

  @impl true
  def handle_cast({:push, data}, q_state(buffer: buf) = state) do
    state
    |> q_state(buffer: buffer_add_data(buf, data))
    |> produce()
    |> noreply()
  end

  def handle_cast({:put, data}, q_state(buffer: buf) = state) do
    state
    |> q_state(buffer: buffer_add_log(buf, data))
    |> produce()
    |> noreply()
  end

  def handle_cast({:mark_delete, key}, q_state(buffer: buf) = state) do
    state
    |> q_state(buffer: buffer_add_deleted(buf, key))
    |> produce()
    |> noreply()
  end

  def handle_cast({:mirrors, sink}, state) do
    state
    |> q_state(mirrors: sink)
    |> noreply()
  end

  defp produce(q_state(consumer: nil) = state), do: state
  defp produce(q_state(in_demand: false) = state), do: state

  defp produce(q_state(consumer: pid) = state) do
    if Process.alive?(pid) do
      state |> produce_to_consumer()
    else
      state |> q_state(consumer: nil)
    end
  end

  defp produce_to_consumer(q_state(buffer: buf, consumer: pid, mirrors: mirrors) = state) do
    case buffer_yield(buf) do
      {:ignored, _} ->
        state

      {payload, new_buf} ->
        GenServer.cast(pid, payload)

        if mirrors do
          Enum.each(mirrors, &GenServer.cast(&1, {:mirror, payload}))
        end

        state |> q_state(buffer: new_buf, in_demand: false)
    end
  end
end
