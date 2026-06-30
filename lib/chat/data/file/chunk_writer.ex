defmodule Chat.Data.File.ChunkWriter do
  @moduledoc "Per-drive serialized chunk write pipeline."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File.ChunkStore

  @registry Chat.Data.File.ChunkPipelineRegistry
  @lanes [:upload, :drive_copy, :network_sync]
  @override_thresholds %{drive_copy: 5, network_sync: 97}
  @max_queue_size 2

  def start_link(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)
    GenServer.start_link(__MODULE__, opts, name: via(drive_id))
  end

  def submit(drive_id, lane, chunk_data, meta) do
    GenServer.call(via(drive_id), {:submit, lane, chunk_data, meta}, :infinity)
  end

  def lane_idle?(drive_id, lane) do
    GenServer.call(via(drive_id), {:lane_idle?, lane})
  end

  @impl true
  def init(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)
    base_dir = Keyword.get(opts, :base_dir)

    state = %{
      drive_id: drive_id,
      base_dir: base_dir,
      queues: Map.new(@lanes, &{&1, :queue.new()}),
      wait_counters: %{drive_copy: 0, network_sync: 0},
      writing: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:submit, lane, chunk_data, meta}, from, state) do
    case {lane, :queue.len(state.queues[lane])} do
      {:upload, len} when len >= @max_queue_size ->
        {:reply, {:busy, 2}, state}

      _ ->
        item = {from, chunk_data, meta}
        queues = Map.update!(state.queues, lane, &:queue.in(item, &1))
        {:noreply, %{state | queues: queues}, {:continue, :next_round}}
    end
  end

  def handle_call({:lane_idle?, lane}, _from, state) do
    idle? = :queue.is_empty(state.queues[lane]) and not writing_lane?(state, lane)
    {:reply, idle?, state}
  end

  @impl true
  def handle_continue(:next_round, state) do
    with nil <- state.writing,
         lane when not is_nil(lane) <- select_lane(state) do
      {{:value, {from, chunk_data, meta}}, queue} = :queue.out(state.queues[lane])
      queues = Map.put(state.queues, lane, queue)

      task =
        Task.async(fn ->
          ChunkStore.put(meta.file_id, meta.chunk_index, chunk_data, state.base_dir)
        end)

      writing = {task.ref, from, lane}
      {:noreply, %{state | queues: queues, writing: writing}}
    else
      _ -> {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, result}, %{writing: {ref, from, lane}} = state) do
    Process.demonitor(ref, [:flush])
    GenServer.reply(from, result)

    state =
      state
      |> Map.put(:writing, nil)
      |> update_counters(lane)

    {:noreply, state, {:continue, :next_round}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{writing: {ref, from, _lane}} = state) do
    GenServer.reply(from, {:error, :write_failed})
    {:noreply, %{state | writing: nil}, {:continue, :next_round}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp select_lane(state) do
    select_override(state) || select_strict(state)
  end

  defp select_override(state) do
    [:drive_copy, :network_sync]
    |> Enum.find(fn lane ->
      not :queue.is_empty(state.queues[lane]) and
        state.wait_counters[lane] >= @override_thresholds[lane]
    end)
  end

  defp select_strict(state) do
    Enum.find(@lanes, fn lane -> not :queue.is_empty(state.queues[lane]) end)
  end

  defp update_counters(state, selected_lane) do
    state.wait_counters
    |> Map.new(fn {lane, count} ->
      cond do
        lane == selected_lane -> {lane, 0}
        :queue.is_empty(state.queues[lane]) -> {lane, count}
        true -> {lane, count + 1}
      end
    end)
    |> tap(fn counters ->
      Enum.each(counters, fn {lane, count} ->
        threshold = @override_thresholds[lane]
        warn_at = div(threshold * 80, 100)

        if count >= warn_at and count < threshold do
          log("#{state.drive_id}: #{lane} wait counter #{count}/#{threshold}", :warning)
        end
      end)
    end)
    |> then(&%{state | wait_counters: &1})
  end

  defp writing_lane?(state, lane) do
    case state.writing do
      {_ref, _from, ^lane} -> true
      _ -> false
    end
  end

  defp via(drive_id) do
    case drive_id do
      id when is_tuple(id) -> id
      id -> {:via, Registry, {@registry, {:writer, id}}}
    end
  end
end
