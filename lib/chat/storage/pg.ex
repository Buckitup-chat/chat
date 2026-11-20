defmodule Chat.Storage.Pg do
  @moduledoc """
  PostgreSQL helpers shared by storage tooling: connection strings for logical
  replication and cluster identity (`system_identifier`).

  Diff+copy lives in `Chat.Storage.Pg.BatchSync`, logical replication in
  `Chat.Storage.Pg.LogicalReplicator`.
  """

  alias Ecto.Adapters.SQL

  @doc """
  Build a PostgreSQL connection string from an Ecto repo configuration.

  ## Options
  - `:port` - Override the port from repo config (useful for dynamically started repos)

  ## Returns
  A connection string in the format: "host=... port=... dbname=... user=... password=..."
  """
  @spec build_connection_string(module(), keyword()) :: String.t()
  def build_connection_string(repo, opts \\ []) do
    config = repo.config()
    host = Keyword.get(config, :hostname, "localhost")
    port = Keyword.get(opts, :port) || Keyword.get(config, :port, 5432)
    database = Keyword.get(config, :database, "chat")
    username = Keyword.get(config, :username, "postgres")
    password = Keyword.get(config, :password, "")

    "host=#{host} port=#{port} dbname=#{database} user=#{username} password=#{password}"
  end

  @doc """
  Returns the PostgreSQL system identifier for the given repo as a string,
  or `nil` when the repo is `nil`, unavailable, or the query fails.
  """
  @spec system_identifier(module() | nil) :: String.t() | nil
  def system_identifier(nil), do: nil

  def system_identifier(repo) do
    case SQL.query(repo, "SELECT system_identifier FROM pg_control_system()", []) do
      {:ok, %{rows: [[id]]}} -> to_string(id)
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
