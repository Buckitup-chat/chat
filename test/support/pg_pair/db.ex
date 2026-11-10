defmodule Chat.Test.PgPairHelper.Db do
  @moduledoc """
  SQL plumbing behind `Chat.Test.PgPairHelper`: database lifecycle and removal of
  replication artifacts (subscriptions, publications, slots).

  `target` is either an Ecto repo (with a checked-out connection) or a Postgrex pid.
  """

  alias Ecto.Adapters.SQL

  @kept_publications ["electric_publication_default"]

  def query!(repo, sql, params \\ [])

  def query!(conn, sql, params) when is_pid(conn), do: Postgrex.query!(conn, sql, params)
  def query!(repo, sql, params), do: SQL.query!(repo, sql, params, log: false)

  def rows(target, sql, params \\ []), do: target |> query!(sql, params) |> Map.fetch!(:rows)

  @doc "Runs `fun` with a short-lived Postgrex connection to `database`."
  def with_conn(repo_config, database, fun) do
    {:ok, conn} =
      repo_config
      |> Keyword.take([:username, :password, :hostname, :port])
      |> Keyword.put(:database, database)
      |> Keyword.put(:backoff_type, :stop)
      |> Postgrex.start_link()

    try do
      fun.(conn)
    after
      GenServer.stop(conn)
    end
  end

  def wal_level(conn), do: conn |> rows("SHOW wal_level") |> then(fn [[level]] -> level end)

  def database_exists?(conn, database),
    do: rows(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [database]) != []

  @doc "Drops `database` (with its subscriptions and slots) when it exists, then creates it empty."
  def recreate_database(repo_config, admin, database) do
    drop_database(repo_config, admin, database)
    query!(admin, ~s(CREATE DATABASE "#{database}"))
  end

  def drop_database(repo_config, admin, database) do
    if database_exists?(admin, database) do
      # PG refuses to drop a database that still owns subscriptions
      with_conn(repo_config, database, &drop_subscriptions/1)
      drop_slots(admin, [database])
      query!(admin, ~s(DROP DATABASE IF EXISTS "#{database}" WITH \(FORCE\)))
    end

    :ok
  end

  @doc "Drops every subscription in the connected database without touching remote slots."
  def drop_subscriptions(target) do
    target
    |> rows(
      "SELECT subname FROM pg_subscription WHERE subdbid = (SELECT oid FROM pg_database WHERE datname = current_database())"
    )
    |> Enum.each(fn [name] ->
      query!(target, ~s(ALTER SUBSCRIPTION "#{name}" DISABLE))
      query!(target, ~s(ALTER SUBSCRIPTION "#{name}" SET \(slot_name = NONE\)))
      query!(target, ~s(DROP SUBSCRIPTION "#{name}"))
    end)
  end

  @doc "Drops publications created by tests (keeps the ones migrations create)."
  def drop_publications(target) do
    target
    |> rows("SELECT pubname FROM pg_publication WHERE NOT (pubname = ANY($1))", [
      @kept_publications
    ])
    |> Enum.each(fn [name] -> query!(target, ~s(DROP PUBLICATION "#{name}")) end)
  end

  @doc "Drops all replication slots that belong to `databases`, terminating walsenders still holding them."
  def drop_slots(target, databases, attempts \\ 50) do
    slots =
      rows(
        target,
        "SELECT slot_name, active_pid FROM pg_replication_slots WHERE database = ANY($1)",
        [databases]
      )

    Enum.each(slots, fn
      [_name, nil] -> :ok
      [_name, pid] -> query!(target, "SELECT pg_terminate_backend($1)", [pid])
    end)

    slots
    |> Enum.map(fn [name, _] -> try_drop_slot(target, name) end)
    |> Enum.all?()
    |> case do
      true ->
        :ok

      false when attempts > 0 ->
        Process.sleep(20)
        drop_slots(target, databases, attempts - 1)

      false ->
        raise "PgPair: could not drop replication slots in #{inspect(databases)}"
    end
  end

  defp try_drop_slot(target, name) do
    query!(target, "SELECT pg_drop_replication_slot($1)", [name])
    true
  rescue
    # still active (walsender not gone yet) or already dropped concurrently
    e in Postgrex.Error ->
      e.postgres[:code] == :undefined_object
  end

  @doc "Empties every public table except `schema_migrations`."
  def truncate_all(target) do
    target
    |> rows(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'"
    )
    |> Enum.map_join(", ", fn [table] -> ~s("#{table}") end)
    |> case do
      "" -> :ok
      tables -> query!(target, "TRUNCATE #{tables} RESTART IDENTITY CASCADE")
    end
  end
end
