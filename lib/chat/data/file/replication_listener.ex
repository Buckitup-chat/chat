defmodule Chat.Data.File.ReplicationListener do
  @moduledoc "Listens for PG replica trigger notifications and activates DriveCopySource."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.DriveCopySource
  alias Chat.Storage.Unit
  alias Chat.TimeKeeper

  @registry Chat.Data.File.ChunkPipelineRegistry

  def start_link(opts) do
    %Unit{id: drive_id} = Keyword.fetch!(opts, :unit)
    GenServer.start_link(__MODULE__, opts, name: via(drive_id))
  end

  @impl true
  def init(opts) do
    %Unit{} = unit = Keyword.fetch!(opts, :unit)
    repo = Unit.repo(unit)
    state = %{drive_id: unit.id, repo: repo, system_id: unit.system_id, conn: nil, refs: %{}}

    case connect_and_listen(repo) do
      {:ok, conn, refs} ->
        {:ok, %{state | conn: conn, refs: refs}}

      {:error, reason} ->
        log("ReplicationListener: failed to connect: #{inspect(reason)}", :warning)
        {:ok, state}
    end
  end

  @impl true
  def handle_info({:notification, _conn, _ref, "file_replicated", payload}, state) do
    case Jason.decode(payload) do
      {:ok, %{"file_id" => file_id, "chunk_count" => chunk_count}} ->
        FileData.insert_missing_chunks_placeholders(
          file_id,
          chunk_count,
          nil,
          TimeKeeper.now_unix(),
          source_drive_id: state.system_id,
          repo: state.repo
        )

      _ ->
        log("ReplicationListener: bad file_replicated payload", :warning)
    end

    {:noreply, state}
  end

  def handle_info({:notification, _conn, _ref, "file_chunk_replicated", payload}, state) do
    case Jason.decode(payload) do
      {:ok, %{"file_id" => fid, "chunk_index" => ci, "data_hash" => dh, "size" => s}} ->
        FileData.fill_missing_chunk(fid, ci, dh, s, repo: state.repo)
        DriveCopySource.chunk_fetchable(state.drive_id, fid, ci, state.system_id)

      _ ->
        log("ReplicationListener: bad file_chunk_replicated payload", :warning)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp connect_and_listen(repo) do
    if Code.ensure_loaded?(repo), do: listen(repo), else: {:error, :no_repo}
  end

  defp listen(repo) do
    pg_opts =
      repo.config()
      |> Keyword.take([:hostname, :port, :database, :username, :password])
      |> Keyword.put_new(:hostname, "localhost")
      |> Keyword.put_new(:database, "chat")

    with {:ok, conn} <- Postgrex.Notifications.start_link(pg_opts),
         {:ok, ref1} <- Postgrex.Notifications.listen(conn, "file_replicated"),
         {:ok, ref2} <- Postgrex.Notifications.listen(conn, "file_chunk_replicated") do
      {:ok, conn, %{file_replicated: ref1, file_chunk_replicated: ref2}}
    end
  end

  defp via(drive_id), do: {:via, Registry, {@registry, {:replication_listener, drive_id}}}
end
