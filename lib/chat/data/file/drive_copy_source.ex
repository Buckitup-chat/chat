defmodule Chat.Data.File.DriveCopySource do
  @moduledoc """
  Event-driven sink for unit-to-unit chunk copy. Reads from other units' ChunkStores.

  Sources are the units registered in `Chat.Storage.Units` other than the own
  one; `{:unit_up, unit}` / `{:unit_down, unit}` on `"storage"` connect and
  disconnect them. A `missing_chunks.source_drive_id` is a unit's PG system id.
  """

  use Chat.Data.File.ChunkSource

  alias Chat.Data.File.ChunkStore
  alias Chat.Storage.Units

  def chunk_fetchable(drive_id, file_id, chunk_index, source_drive_id) do
    GenServer.cast(via(drive_id), {:chunk_fetchable, file_id, chunk_index, source_drive_id})
  end

  @impl Chat.Data.File.ChunkSource
  def registry_key, do: :drive_copy_source

  @impl Chat.Data.File.ChunkSource
  def writer_tag, do: :drive_copy

  @impl Chat.Data.File.ChunkSource
  def init_extra(_opts), do: %{}

  @impl Chat.Data.File.ChunkSource
  def on_init(state) do
    Phoenix.PubSub.subscribe(Chat.PubSub, "storage")
    Phoenix.PubSub.subscribe(Chat.PubSub, "chunk_pipeline")
    state
  end

  @impl Chat.Data.File.ChunkSource
  def can_poll?(state), do: other_units(state) != []

  @impl Chat.Data.File.ChunkSource
  def handle_source_cast({:unit_up, unit}, state) do
    if own?(state, unit),
      do: {:source_disconnected, unit.system_id, state},
      else: {:source_connected, unit.system_id, state}
  end

  def handle_source_cast({:unit_down, unit}, state),
    do: {:source_disconnected, unit.system_id, state}

  @impl Chat.Data.File.ChunkSource
  def source_connected?(state, system_id), do: source_unit(state, system_id) != nil

  @impl Chat.Data.File.ChunkSource
  def poll_query(limit, repo),
    do: FileData.fetchable_missing_chunks_for_copy(limit, nil, repo: repo)

  @impl Chat.Data.File.ChunkSource
  def sweep_query(source_drive_id, repo),
    do: FileData.missing_chunks_for_drive(source_drive_id, repo: repo)

  @impl Chat.Data.File.ChunkSource
  def chunk_source_id(mc), do: mc.source_drive_id

  @doc """
  Fetches from the unit with `source_drive_id` first, then from every other
  unit in turn.
  """
  @impl Chat.Data.File.ChunkSource
  def fetch_chunk(state, file_id, chunk_index, source_drive_id) do
    primary = source_unit(state, source_drive_id)
    fallbacks = state |> other_units() |> Enum.reject(&(&1 == primary))

    [primary | fallbacks]
    |> Enum.reject(&is_nil/1)
    |> try_fetch(file_id, chunk_index, {:error, :no_source})
    |> tap(&log_fetch_result(&1, file_id, chunk_index, primary))
  end

  @impl Chat.Data.File.ChunkSource
  def handle_extra_info({event, unit}, state) when event in [:unit_up, :unit_down],
    do: handle_cast({event, unit}, state)

  def handle_extra_info({:chunk_pipeline, :pg_diff_copied}, state) do
    log("retriggering drive copy after pg replication finished", :info)
    {:noreply, state |> enqueue_poll() |> drain()}
  end

  def handle_extra_info({:chunk_pipeline, :backfill_done}, state) do
    log("retriggering drive copy after backfill finished", :info)
    {:noreply, state |> enqueue_poll() |> drain()}
  end

  def handle_extra_info(_msg, state), do: {:noreply, state}

  # Sources

  defp other_units(state), do: Units.others(state.unit)

  defp source_unit(_state, nil), do: nil

  defp source_unit(state, system_id) do
    case Units.by_system_id(system_id) do
      {:ok, unit} -> if own?(state, unit), do: nil, else: unit
      :error -> nil
    end
  end

  # Units are unique per role
  defp own?(state, unit), do: unit.role == state.unit.role

  defp try_fetch([], _file_id, _chunk_index, last_result), do: last_result

  defp try_fetch([unit | rest], file_id, chunk_index, _last_result) do
    case ChunkStore.fetch(unit, file_id, chunk_index) do
      {:ok, _body} = ok -> ok
      error -> try_fetch(rest, file_id, chunk_index, error)
    end
  end

  defp log_fetch_result({:ok, _}, _file_id, _chunk_index, _primary), do: :ok

  defp log_fetch_result({:error, reason}, file_id, chunk_index, primary) do
    primary_id = primary && primary.id

    log(
      "#{file_id}:#{chunk_index} no unit has it (#{inspect(reason)}), primary: #{inspect(primary_id)}",
      :warning
    )
  end
end
