defmodule Chat.Data.File.DriveAnnouncer do
  @moduledoc "Announces drive mount/unmount on chunk_pipeline PubSub using PG system identifier."

  use GenServer

  alias Ecto.Adapters.SQL

  @topic "chunk_pipeline"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl GenServer
  def init(opts) do
    repo = Keyword.get(opts, :repo)
    Process.flag(:trap_exit, true)

    case query_system_id(repo) do
      {:ok, system_id} ->
        broadcast({:drive_mounted, system_id})
        {:ok, system_id}

      {:error, _reason} ->
        :ignore
    end
  end

  @impl GenServer
  def terminate(_reason, system_id) do
    broadcast({:drive_unmounted, system_id})
    :ok
  end

  defp query_system_id(nil), do: {:error, :no_repo}

  defp query_system_id(repo) do
    case SQL.query(repo, "SELECT system_identifier FROM pg_control_system()", []) do
      {:ok, %{rows: [[identifier]]}} -> {:ok, to_string(identifier)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Chat.PubSub, @topic, {:chunk_pipeline, event})
  end
end
