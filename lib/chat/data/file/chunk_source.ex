defmodule Chat.Data.File.ChunkSource do
  @moduledoc "Shared pipeline behaviour for chunk fetch sources (drive copy, network sync)."

  @callback registry_key() :: atom()
  @callback writer_tag() :: atom()
  @callback init_extra(keyword()) :: map()
  @callback on_init(map()) :: map()
  @callback handle_source_cast(tuple(), map()) ::
              {:source_connected, term(), map()} | {:source_disconnected, term(), map()}
  @callback source_connected?(map(), term()) :: boolean()
  @callback can_poll?(map()) :: boolean()
  @callback poll_query(pos_integer(), term()) :: [map()]
  @callback sweep_query(term(), term()) :: [map()]
  @callback chunk_source_id(map()) :: term()
  @callback fetch_chunk(map(), binary(), non_neg_integer(), term()) ::
              {:ok, binary()} | {:error, term()}
  @callback handle_extra_info(term(), map()) :: {:noreply, map()}

  @optional_callbacks [on_init: 1, can_poll?: 1, handle_extra_info: 2]

  defmacro __using__(_opts) do
    quote location: :keep do
      use GenServer
      use Toolbox.OriginLog

      alias Chat.Data.File, as: FileData
      alias Chat.Data.File.ChunkWriter
      alias Chat.Data.Types.FileChunkDataHash
      alias Chat.TimeKeeper

      @behaviour Chat.Data.File.ChunkSource

      @registry Chat.Data.File.ChunkPipelineRegistry
      @poll_interval :timer.hours(1)
      @batch_size 5
      @max_to_write 3
      @max_writing 2

      @impl Chat.Data.File.ChunkSource
      def on_init(state), do: state
      @impl Chat.Data.File.ChunkSource
      def can_poll?(_state), do: true
      @impl Chat.Data.File.ChunkSource
      def handle_extra_info(_msg, state), do: {:noreply, state}

      defoverridable on_init: 1, can_poll?: 1, handle_extra_info: 2

      def start_link(opts),
        do: GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :drive_id)))

      @impl GenServer
      def init(opts) do
        schedule_poll()

        state =
          %{
            drive_id: Keyword.fetch!(opts, :drive_id),
            repo: Keyword.get(opts, :repo),
            sweep_timers: %{},
            to_fetch: :queue.new(),
            fetching: %{},
            to_write: :queue.new(),
            to_write_len: 0,
            writing: %{}
          }
          |> Map.merge(init_extra(opts))
          |> on_init()

        {:ok, state, {:continue, :initial_poll}}
      end

      @impl GenServer
      def handle_continue(:initial_poll, state),
        do: {:noreply, state |> enqueue_poll() |> drain()}

      @impl GenServer
      def handle_cast({:chunk_fetchable, file_id, chunk_index, source_id}, state) do
        {:noreply, state |> enqueue(file_id, chunk_index, source_id) |> drain()}
      end

      def handle_cast(event, state) do
        case handle_source_cast(event, state) do
          {:source_connected, source_id, state} ->
            timer_ref = Process.send_after(self(), {:sweep, source_id}, 5_000)
            timers = Map.put(state.sweep_timers, source_id, timer_ref)
            {:noreply, %{state | sweep_timers: timers}}

          {:source_disconnected, source_id, state} ->
            {timer_ref, timers} = Map.pop(state.sweep_timers, source_id)
            if timer_ref, do: Process.cancel_timer(timer_ref)
            {:noreply, %{state | sweep_timers: timers}}
        end
      end

      @impl GenServer
      def handle_info(:poll, state) do
        schedule_poll()
        {:noreply, state |> enqueue_poll() |> drain()}
      end

      def handle_info({:sweep, source_id}, state) do
        state = %{state | sweep_timers: Map.delete(state.sweep_timers, source_id)}

        state =
          if source_connected?(state, source_id),
            do: enqueue_sweep(state, source_id),
            else: state

        {:noreply, drain(state)}
      end

      def handle_info({ref, result}, state) when is_reference(ref) do
        Process.demonitor(ref, [:flush])
        {:noreply, state |> handle_task_result(ref, result) |> drain()}
      end

      def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
        state =
          cond do
            Map.has_key?(state.fetching, ref) -> drop_tracked(state, ref, :fetching)
            Map.has_key?(state.writing, ref) -> drop_tracked(state, ref, :writing)
            true -> state
          end

        {:noreply, drain(state)}
      end

      def handle_info(msg, state), do: handle_extra_info(msg, state)

      defp drain(state) do
        state
        |> drain_writing()
        |> refill_if_idle()
        |> drain_fetching()
      end

      defp drain_writing(state) do
        if map_size(state.writing) < @max_writing and not :queue.is_empty(state.to_write) do
          {{:value, {file_id, chunk_index, body}}, to_write} = :queue.out(state.to_write)

          %{state | to_write: to_write, to_write_len: state.to_write_len - 1}
          |> start_write_task(file_id, chunk_index, body)
          |> drain_writing()
        else
          state
        end
      end

      defp refill_if_idle(state) do
        fetch_cap = 3 * (@max_to_write - state.to_write_len)

        if :queue.is_empty(state.to_fetch) and map_size(state.fetching) < fetch_cap,
          do: enqueue_poll(state),
          else: state
      end

      defp drain_fetching(state) do
        fetch_cap = 3 * (@max_to_write - state.to_write_len)

        if map_size(state.fetching) < fetch_cap and not :queue.is_empty(state.to_fetch) do
          {{:value, {file_id, chunk_index, source_id}}, to_fetch} = :queue.out(state.to_fetch)

          %{state | to_fetch: to_fetch}
          |> start_fetch_task(file_id, chunk_index, source_id)
          |> drain_fetching()
        else
          state
        end
      end

      defp handle_task_result(state, ref, result) do
        case result do
          {:fetched, file_id, chunk_index, body} ->
            pop_fetching(state, ref) |> enqueue_write(file_id, chunk_index, body)

          {:fetch_failed, file_id, chunk_index} ->
            record_failure(state, file_id, chunk_index)
            pop_fetching(state, ref)

          {:written, file_id, chunk_index} ->
            FileData.delete_missing_chunk(file_id, chunk_index, repo: state.repo)
            pop_writing(state, ref)

          {:write_failed, file_id, chunk_index} ->
            record_failure(state, file_id, chunk_index)
            pop_writing(state, ref)
        end
      end

      defp pop_fetching(state, ref), do: %{state | fetching: Map.delete(state.fetching, ref)}
      defp pop_writing(state, ref), do: %{state | writing: Map.delete(state.writing, ref)}

      defp enqueue(state, file_id, chunk_index, source_id),
        do: %{state | to_fetch: :queue.in({file_id, chunk_index, source_id}, state.to_fetch)}

      defp enqueue_write(state, file_id, chunk_index, body) do
        %{
          state
          | to_write: :queue.in({file_id, chunk_index, body}, state.to_write),
            to_write_len: state.to_write_len + 1
        }
      end

      defp enqueue_poll(state) do
        if Chat.Db.repo_ready?(repo_module(state)) and can_poll?(state) do
          in_pipeline = in_pipeline_keys(state)
          limit = MapSet.size(in_pipeline) + @batch_size

          poll_query(limit, state.repo)
          |> Enum.reject(fn mc -> MapSet.member?(in_pipeline, {mc.file_id, mc.chunk_index}) end)
          |> Enum.reduce(state, fn mc, acc ->
            enqueue(acc, mc.file_id, mc.chunk_index, chunk_source_id(mc))
          end)
        else
          state
        end
      end

      defp in_pipeline_keys(state) do
        (Map.values(state.fetching) ++
           Map.values(state.writing) ++
           queue_keys(state.to_fetch) ++ queue_keys(state.to_write))
        |> MapSet.new()
      end

      defp queue_keys(q),
        do: :queue.to_list(q) |> Enum.map(fn {fid, ci, _} -> {fid, ci} end)

      defp enqueue_sweep(state, source_id) do
        if Chat.Db.repo_ready?(repo_module(state)) do
          sweep_query(source_id, state.repo)
          |> Enum.reduce(state, fn mc, acc ->
            enqueue(acc, mc.file_id, mc.chunk_index, source_id)
          end)
        else
          state
        end
      end

      defp start_fetch_task(state, file_id, chunk_index, source_id) do
        repo = state.repo

        task =
          Task.Supervisor.async_nolink(Chat.TaskSupervisor, fn ->
            with {:ok, body} <- fetch_chunk(state, file_id, chunk_index, source_id),
                 :ok <- verify_hash(repo, file_id, chunk_index, body) do
              {:fetched, file_id, chunk_index, body}
            else
              {:error, reason} ->
                log("#{file_id}:#{chunk_index} fetch failed: #{inspect(reason)}", :warning)
                {:fetch_failed, file_id, chunk_index}
            end
          end)

        %{state | fetching: Map.put(state.fetching, task.ref, {file_id, chunk_index})}
      end

      defp start_write_task(state, file_id, chunk_index, body) do
        %{drive_id: drive_id} = state
        tag = writer_tag()
        meta = %{file_id: file_id, chunk_index: chunk_index}

        task =
          Task.Supervisor.async_nolink(Chat.TaskSupervisor, fn ->
            case ChunkWriter.submit(drive_id, tag, body, meta) do
              :ok -> {:written, file_id, chunk_index}
              {:error, _} -> {:write_failed, file_id, chunk_index}
            end
          end)

        %{state | writing: Map.put(state.writing, task.ref, {file_id, chunk_index})}
      end

      defp drop_tracked(state, ref, field) do
        {file_id, chunk_index} = state |> Map.fetch!(field) |> Map.fetch!(ref)
        record_failure(state, file_id, chunk_index)
        Map.update!(state, field, &Map.delete(&1, ref))
      end

      defp verify_hash(repo, file_id, chunk_index, body) do
        expected = FileData.get_missing_chunk_hash(file_id, chunk_index, repo: repo)
        actual = body |> EnigmaPq.hash() |> FileChunkDataHash.from_binary()
        if actual == expected, do: :ok, else: {:error, :hash_mismatch}
      end

      defp record_failure(%{repo: repo}, file_id, chunk_index) do
        FileData.increment_missing_chunk_attempts(file_id, chunk_index, TimeKeeper.now_unix(),
          repo: repo
        )
      end

      defp repo_module(%{repo: nil}), do: Chat.Db.repo()
      defp repo_module(%{repo: repo}), do: repo
      defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)
      defp via(drive_id), do: {:via, Registry, {@registry, {registry_key(), drive_id}}}
    end
  end
end
