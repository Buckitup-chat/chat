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
  def can_poll?(state), do: MapSet.size(state.peers) > 0

  @impl Chat.Data.File.ChunkSource
  def poll_query(limit, repo),
    do: FileData.fetchable_missing_chunks_for_sync(limit, nil, repo: repo)

  @impl Chat.Data.File.ChunkSource
  def sweep_query(peer_url, repo),
    do: FileData.missing_chunks_for_peer(peer_url, repo: repo)

  @impl Chat.Data.File.ChunkSource
  def chunk_source_id(mc), do: mc.peer_url

  @impl Chat.Data.File.ChunkSource
  def fetch_chunk(state, file_id, chunk_index, peer_url) do
    peer_url
    |> peers_to_try(state)
    |> try_fetch(file_id, chunk_index)
  end

  defp peers_to_try(nil, state), do: connected_peers(state)
  defp peers_to_try(peer_url, state), do: [peer_url | connected_peers_except(state, peer_url)]

  defp connected_peers(state), do: MapSet.to_list(state.peers)

  defp connected_peers_except(state, peer_url),
    do: state.peers |> MapSet.delete(peer_url) |> MapSet.to_list()

  defp try_fetch([], _file_id, _chunk_index), do: {:error, :no_peer}

  defp try_fetch([peer_url | rest], file_id, chunk_index) do
    url = "#{peer_url}/electric/v1/file_chunk/#{file_id}/#{chunk_index}"

    case Req.get(url, receive_timeout: @fetch_timeout) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      _ when rest != [] -> try_fetch(rest, file_id, chunk_index)
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
