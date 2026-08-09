defmodule Chat.Data.File.DriveCopySource do
  @moduledoc "Event-driven sink for drive-to-drive chunk copy. Reads from other drives' ChunkStores."

  use Chat.Data.File.ChunkSource

  alias Chat.Data.File.ChunkStore
  alias Ecto.Adapters.SQL

  def chunk_fetchable(drive_id, file_id, chunk_index, source_drive_id) do
    GenServer.cast(via(drive_id), {:chunk_fetchable, file_id, chunk_index, source_drive_id})
  end

  @impl Chat.Data.File.ChunkSource
  def registry_key, do: :drive_copy_source

  @impl Chat.Data.File.ChunkSource
  def writer_tag, do: :drive_copy

  @impl Chat.Data.File.ChunkSource
  def init_extra(opts), do: %{other_drives: %{}, base_dir: Keyword.get(opts, :base_dir)}

  @impl Chat.Data.File.ChunkSource
  def on_init(state) do
    Phoenix.PubSub.subscribe(Chat.PubSub, "chunk_pipeline")
    scan_drives(state)
  end

  @impl Chat.Data.File.ChunkSource
  def can_poll?(state), do: map_size(state.other_drives) > 0

  @impl Chat.Data.File.ChunkSource
  def handle_source_cast({:drive_mounted, system_id}, state) do
    if system_id == own_system_id(state) do
      {:source_disconnected, system_id, state}
    else
      state = scan_drives(state)
      {:source_connected, system_id, state}
    end
  end

  def handle_source_cast({:drive_unmounted, system_id}, state) do
    others = Map.delete(state.other_drives, system_id)
    {:source_disconnected, system_id, %{state | other_drives: others}}
  end

  @impl Chat.Data.File.ChunkSource
  def source_connected?(state, system_id), do: Map.has_key?(state.other_drives, system_id)

  @impl Chat.Data.File.ChunkSource
  def poll_query(limit, repo),
    do: FileData.fetchable_missing_chunks_for_copy(limit, nil, repo: repo)

  @impl Chat.Data.File.ChunkSource
  def sweep_query(source_drive_id, repo),
    do: FileData.missing_chunks_for_drive(source_drive_id, repo: repo)

  @impl Chat.Data.File.ChunkSource
  def chunk_source_id(mc), do: mc.source_drive_id

  @impl Chat.Data.File.ChunkSource
  def fetch_chunk(state, file_id, chunk_index, source_drive_id) do
    source_dir = Map.get(state.other_drives, source_drive_id)

    with {:error, reason} <- try_fetch(source_dir, file_id, chunk_index) do
      fallback_dir = state.other_drives |> Map.delete(source_drive_id) |> pick_random_drive()

      try_fetch(fallback_dir, file_id, chunk_index)
      |> tap(&log_fetch_result(&1, file_id, chunk_index, reason, source_dir, fallback_dir))
    end
  end

  @impl Chat.Data.File.ChunkSource
  def handle_extra_info({:chunk_pipeline, :backfill_done}, state),
    do: {:noreply, state |> enqueue_poll() |> drain()}

  def handle_extra_info({:chunk_pipeline, event}, state), do: handle_cast(event, state)
  def handle_extra_info(_msg, state), do: {:noreply, state}

  # Scanning

  defp scan_drives(%{base_dir: nil} = state), do: state

  defp scan_drives(state) do
    state.base_dir
    |> media_root()
    |> discover_drives()
    |> Enum.reject(fn {sys_id, _} -> sys_id == own_system_id(state) end)
    |> Map.new()
    |> then(&%{state | other_drives: &1})
  end

  defp media_root(base_dir) do
    base_dir
    |> Path.join("../../..")
    |> Path.expand()
  end

  defp discover_drives(media_root) do
    usb_drives =
      Path.wildcard(Path.join(media_root, "sd*"))
      |> Enum.flat_map(fn device_path ->
        device = Path.basename(device_path)
        base_dir = drive_base_dir(device_path)

        if File.dir?(Path.join(base_dir, "pq_files")) do
          case query_system_id(device) do
            {:ok, system_id} -> [{system_id, base_dir}]
            _ -> []
          end
        else
          []
        end
      end)

    internal_drive =
      case query_system_id(Chat.Repo) do
        {:ok, system_id} ->
          [{system_id, Chat.Db.internal_files_dir()}]

        _ ->
          []
      end

    usb_drives ++ internal_drive
  end

  defp drive_base_dir(device_path) do
    Path.join([device_path, "main_db", Chat.Db.version_path() <> "_files"])
  end

  defp own_system_id(%{repo: repo}) do
    case query_system_id(repo) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp query_system_id(repo) when is_atom(repo) do
    case SQL.query(repo, "SELECT system_identifier FROM pg_control_system()", []) do
      {:ok, %{rows: [[identifier]]}} -> {:ok, to_string(identifier)}
      _ -> :error
    end
  end

  defp query_system_id(device) when is_binary(device) do
    repo = device_repo(device)

    if function_exported?(repo, :config, 0) do
      query_system_id(repo)
    else
      :error
    end
  end

  defp device_repo(device) do
    "sd" <> <<index::bitstring-size(8)>> <> _ = device
    Module.concat([Platform.Dev, :"Sd#{index}", Repo])
  end

  # Helpers

  defp log_fetch_result({:ok, _}, file_id, chunk_index, reason, source_dir, _fallback_dir),
    do: log("#{file_id}:#{chunk_index} primary failed (#{inspect(reason)}, dir: #{inspect(source_dir)}), fallback ok", :info)

  defp log_fetch_result({:error, fallback_reason}, file_id, chunk_index, reason, source_dir, fallback_dir),
    do: log("#{file_id}:#{chunk_index} both failed — primary: #{inspect(reason)} (#{inspect(source_dir)}), fallback: #{inspect(fallback_reason)} (#{inspect(fallback_dir)})", :warning)

  defp try_fetch(nil, _file_id, _chunk_index), do: {:error, :no_source}

  defp try_fetch(source_dir, file_id, chunk_index),
    do: ChunkStore.fetch(file_id, chunk_index, source_dir)

  defp pick_random_drive(drives) when map_size(drives) == 0, do: nil
  defp pick_random_drive(drives), do: drives |> Map.values() |> Enum.random()
end
