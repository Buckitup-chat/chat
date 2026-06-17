defmodule Chat.Data.File.ChunkFetcher do
  @moduledoc "Fetches missing chunk bytes from peers and admits them to ChunkStore."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.IpfsStore
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.TimeKeeper

  @poll_interval :timer.seconds(30)
  @batch_size 10
  @max_attempts 10
  @fetch_timeout :timer.seconds(60)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  def trigger_fetch do
    GenServer.cast(__MODULE__, :fetch_now)
  end

  @impl true
  def init(:ok) do
    schedule_poll()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    fetch_missing_chunks()
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast(:fetch_now, state) do
    fetch_missing_chunks()
    {:noreply, state}
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)

  defp fetch_missing_chunks do
    if Chat.Db.repo_ready?() do
      FileData.fetchable_missing_chunks(@batch_size, @max_attempts)
      |> Enum.each(&fetch_one/1)
    end
  end

  defp fetch_one(missing) do
    url = "#{missing.peer_url}/electric/v1/file_chunk/#{missing.file_id}/#{missing.chunk_index}"

    case Req.get(url, receive_timeout: @fetch_timeout) do
      {:ok, %{status: 200, body: body}} ->
        admit_chunk(missing, body)

      {:ok, %{status: status}} ->
        log("ChunkFetcher: #{status} for #{missing.file_id}:#{missing.chunk_index}", :warning)
        bump_attempts(missing)

      {:error, reason} ->
        log(
          "ChunkFetcher: fetch error for #{missing.file_id}:#{missing.chunk_index}: #{inspect(reason)}",
          :warning
        )

        bump_attempts(missing)
    end
  end

  defp admit_chunk(%{data_hash: expected_hash} = missing, body) do
    actual_hash = body |> EnigmaPq.hash() |> FileChunkDataHash.from_binary()

    if actual_hash == expected_hash do
      store_chunk(missing, body)
    else
      log("ChunkFetcher: hash mismatch for #{missing.file_id}:#{missing.chunk_index}", :warning)
      bump_attempts(missing)
    end
  end

  defp store_chunk(missing, body) do
    with {:ok, ipfs_cid} <- IpfsStore.put(body),
         :ok <- verify_cid(missing, ipfs_cid) do
      FileData.delete_missing_chunk(missing.file_id, missing.chunk_index)
      log("ChunkFetcher: admitted #{missing.file_id}:#{missing.chunk_index}", :debug)
    else
      {:error, :cid_mismatch} ->
        log(
          "ChunkFetcher: CID mismatch for #{missing.file_id}:#{missing.chunk_index}",
          :warning
        )

        bump_attempts(missing)

      error ->
        log(
          "ChunkFetcher: store failed #{missing.file_id}:#{missing.chunk_index}: #{inspect(error)}",
          :warning
        )

        bump_attempts(missing)
    end
  end

  defp verify_cid(%{cid: expected_cid}, ipfs_cid) when is_binary(expected_cid) do
    if expected_cid == ipfs_cid, do: :ok, else: {:error, :cid_mismatch}
  end

  defp verify_cid(_missing, _ipfs_cid), do: :ok

  defp bump_attempts(missing) do
    FileData.increment_missing_chunk_attempts(
      missing.file_id,
      missing.chunk_index,
      TimeKeeper.now_unix()
    )
  end
end
