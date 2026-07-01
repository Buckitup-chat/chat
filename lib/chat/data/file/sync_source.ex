defmodule Chat.Data.File.SyncSource do
  @moduledoc "Event-driven sink for network-synced chunks. Fetches from peers, submits to ChunkWriter."

  use Chat.Data.File.ChunkSource

  @fetch_timeout :timer.seconds(60)

  def chunk_fetchable(drive_id, file_id, chunk_index, peer_url) do
    GenServer.cast(via(drive_id), {:chunk_fetchable, file_id, chunk_index, peer_url})
  end

  def peer_connected(drive_id, peer_url) do
    GenServer.cast(via(drive_id), {:peer_connected, peer_url})
  end

  def peer_disconnected(drive_id, peer_url) do
    GenServer.cast(via(drive_id), {:peer_disconnected, peer_url})
  end

  # ChunkSource callbacks

  @impl Chat.Data.File.ChunkSource
  def registry_key, do: :sync_source

  @impl Chat.Data.File.ChunkSource
  def writer_tag, do: :network_sync

  @impl Chat.Data.File.ChunkSource
  def init_extra(_opts), do: %{peers: MapSet.new()}

  @impl Chat.Data.File.ChunkSource
  def handle_source_cast({:peer_connected, peer_url}, state) do
    peers = MapSet.put(state.peers, peer_url)
    {:source_connected, peer_url, %{state | peers: peers}}
  end

  def handle_source_cast({:peer_disconnected, peer_url}, state) do
    peers = MapSet.delete(state.peers, peer_url)
    {:source_disconnected, peer_url, %{state | peers: peers}}
  end

  @impl Chat.Data.File.ChunkSource
  def source_connected?(state, peer_url), do: MapSet.member?(state.peers, peer_url)

  @impl Chat.Data.File.ChunkSource
  def poll_query(limit, repo),
    do: FileData.fetchable_missing_chunks_for_sync(limit, nil, repo: repo)

  @impl Chat.Data.File.ChunkSource
  def sweep_query(peer_url, repo),
    do: FileData.missing_chunks_for_peer(peer_url, repo: repo)

  @impl Chat.Data.File.ChunkSource
  def chunk_source_id(mc), do: mc.peer_url

  @impl Chat.Data.File.ChunkSource
  def fetch_chunk(_state, file_id, chunk_index, peer_url) do
    url = "#{peer_url}/electric/v1/file_chunk/#{file_id}/#{chunk_index}"

    case Req.get(url, receive_timeout: @fetch_timeout) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
