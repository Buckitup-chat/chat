defmodule Chat.Data.File.DriveCopySource do
  @moduledoc "Event-driven sink for drive-to-drive chunk copy. Reads from other drives' ChunkStores."

  use Chat.Data.File.ChunkSource

  alias Chat.Data.File.ChunkStore

  def chunk_fetchable(drive_id, file_id, chunk_index, source_drive_id) do
    GenServer.cast(via(drive_id), {:chunk_fetchable, file_id, chunk_index, source_drive_id})
  end

  def drive_mounted(drive_id, other_drive_id, base_dir) do
    GenServer.cast(via(drive_id), {:drive_mounted, other_drive_id, base_dir})
  end

  def drive_unmounted(drive_id, other_drive_id) do
    GenServer.cast(via(drive_id), {:drive_unmounted, other_drive_id})
  end

  # ChunkSource callbacks

  @impl Chat.Data.File.ChunkSource
  def registry_key, do: :drive_copy_source

  @impl Chat.Data.File.ChunkSource
  def writer_tag, do: :drive_copy

  @impl Chat.Data.File.ChunkSource
  def init_extra(_opts), do: %{other_drives: %{}}

  @impl Chat.Data.File.ChunkSource
  def on_init(state) do
    Phoenix.PubSub.subscribe(Chat.PubSub, "chunk_pipeline")
    state
  end

  @impl Chat.Data.File.ChunkSource
  def can_poll?(state), do: map_size(state.other_drives) > 0

  @impl Chat.Data.File.ChunkSource
  def handle_source_cast({:drive_mounted, drive_id, _}, %{drive_id: drive_id} = state) do
    {:source_disconnected, drive_id, state}
  end

  def handle_source_cast({:drive_mounted, other_drive_id, base_dir}, state) do
    others = Map.put(state.other_drives, other_drive_id, base_dir)
    {:source_connected, other_drive_id, %{state | other_drives: others}}
  end

  def handle_source_cast({:drive_unmounted, other_drive_id}, state) do
    others = Map.delete(state.other_drives, other_drive_id)
    {:source_disconnected, other_drive_id, %{state | other_drives: others}}
  end

  @impl Chat.Data.File.ChunkSource
  def source_connected?(state, drive_id), do: Map.has_key?(state.other_drives, drive_id)

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
    source_dir = resolve_source_dir(state.other_drives, source_drive_id)
    ChunkStore.fetch(file_id, chunk_index, source_dir)
  end

  @impl Chat.Data.File.ChunkSource
  def handle_extra_info({:chunk_pipeline, event}, state), do: handle_cast(event, state)
  def handle_extra_info(_msg, state), do: {:noreply, state}

  # Helpers

  defp resolve_source_dir(other_drives, source_drive_id) when is_binary(source_drive_id) do
    Map.get(other_drives, source_drive_id) || pick_random_drive(other_drives)
  end

  defp resolve_source_dir(other_drives, _), do: pick_random_drive(other_drives)

  defp pick_random_drive(drives) when map_size(drives) == 0, do: nil
  defp pick_random_drive(drives), do: drives |> Map.values() |> Enum.random()
end
