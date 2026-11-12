defmodule Chat.Test.PgPairHelper do
  @moduledoc """
  Two-database PG test infra: `chat_test_unit_a` / `chat_test_unit_b` on the host PG,
  served by `Chat.Test.UnitARepo` / `Chat.Test.UnitBRepo`. Use via `Chat.Test.PgPairCase`.

  The pair is created lazily (first `:pg_pair` module), migrated with Chat migrations
  and dropped after the suite together with its subscriptions, publications and slots.
  Both databases live in the same cluster, so they share one `system_id/1`.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  alias Chat.Storage.Unit
  alias Chat.Test.PgPairHelper.Db
  alias Chat.Test.{UnitARepo, UnitBRepo}
  alias Ecto.Adapters.SQL.Sandbox

  @repos [UnitARepo, UnitBRepo]
  @ready_key {__MODULE__, :ready}
  @poll_ms 20
  @conninfo_keys %{
    hostname: :host,
    port: :port,
    username: :user,
    password: :password,
    database: :dbname
  }

  def repos, do: @repos

  @doc "Creates and migrates the pair once per test run. Raises unless host PG has `wal_level=logical`."
  def ensure_ready do
    :global.trans({__MODULE__, self()}, fn ->
      unless :persistent_term.get(@ready_key, false) do
        setup_pair()
        :persistent_term.put(@ready_key, true)
      end
    end)

    :ok
  end

  @doc "Checks out both repos: `:sandbox` (rolled back) or `:committed` (no transaction, rows are visible to replication)."
  def checkout(mode, shared?) do
    Enum.each(@repos, fn repo ->
      :ok = Sandbox.checkout(repo, sandbox: mode == :sandbox)
      if shared?, do: Sandbox.mode(repo, {:shared, self()})
    end)
  end

  @doc "Removes everything a committed test left behind: subscriptions, publications, slots and rows."
  def reset do
    Enum.each(@repos, fn repo ->
      :ok = Sandbox.checkout(repo, sandbox: false)
      Db.drop_subscriptions(repo)
    end)

    Db.drop_slots(UnitARepo, databases())

    Enum.each(@repos, fn repo ->
      Db.drop_publications(repo)
      Db.truncate_all(repo)
      Sandbox.checkin(repo)
    end)
  end

  @doc """
  Replicates `tables` from `from` to `to` via logical replication.

  The slot is created separately and the subscription uses `create_slot = false`:
  a same-cluster `CREATE SUBSCRIPTION` with `create_slot = true` hangs.
  Needs committed mode.
  """
  def subscribe(from, to, name, tables) do
    Db.query!(from, ~s(CREATE PUBLICATION "#{name}" FOR TABLE #{Enum.join(tables, ", ")}))
    Db.query!(from, "SELECT pg_create_logical_replication_slot($1, 'pgoutput')", [name])

    Db.query!(to, """
    CREATE SUBSCRIPTION "#{name}" CONNECTION '#{conninfo(from)}' PUBLICATION "#{name}"
    WITH (create_slot = false, slot_name = '#{name}', copy_data = false)
    """)

    :ok
  end

  @doc "Polls `repo` until `queryable` returns rows; returns them. Flunks after `timeout` ms."
  def await_replicated(repo, queryable, timeout \\ 5_000) do
    case repo.all(queryable) do
      [] when timeout <= 0 ->
        flunk("#{inspect(queryable)} not replicated to #{inspect(repo)} in time")

      [] ->
        Process.sleep(@poll_ms)
        await_replicated(repo, queryable, timeout - @poll_ms)

      rows ->
        rows
    end
  end

  @doc "PG system identifier of the cluster `repo` connects to."
  def system_id(repo) do
    repo
    |> Db.rows("SELECT system_identifier FROM pg_control_system()")
    |> then(fn [[id]] -> id end)
  end

  @doc """
  `%Chat.Storage.Unit{}` on `repo` (pinned by id in `config :chat, Chat.Storage, repos:`)
  with a real temporary `pq_files` dir under `root`.

  `unit_a` is `:main`, `unit_b` is `:backup` (the app's own internal unit holds `:internal`). Both databases share one cluster, so
  their real `system_id/1` is equal; the fixtures carry distinct fake ids instead,
  which is what links and `missing_chunks.source_drive_id` tell apart.
  """
  def unit_fixture(repo, root) do
    {id, role} = if repo == UnitARepo, do: {"unit_a", :main}, else: {"unit_b", :backup}

    %Unit{id: id, role: role, root: root, system_id: "sys_#{id}"}
    |> tap(&(&1 |> Unit.path(:pq_files) |> File.mkdir_p!()))
  end

  def databases, do: Enum.map(@repos, &(&1.config() |> Keyword.fetch!(:database)))

  defp setup_pair do
    with_admin(fn admin ->
      assert_logical_wal!(admin)
      Enum.each(databases(), &Db.recreate_database(base_config(), admin, &1))
    end)

    Enum.each(@repos, &start_and_migrate/1)
    ExUnit.after_suite(fn _ -> teardown() end)
  end

  defp teardown do
    Enum.each(@repos, fn repo ->
      Sandbox.mode(repo, :auto)
      Db.drop_subscriptions(repo)
      repo.stop()
    end)

    with_admin(fn admin ->
      Enum.each(databases(), &Db.drop_database(base_config(), admin, &1))
    end)

    :persistent_term.erase(@ready_key)
  end

  defp start_and_migrate(repo) do
    {:ok, pid} = repo.start_link()
    # owned by the run, not by the setup_all process that happens to start it
    Process.unlink(pid)

    # each run loads the migration files again — silence "redefining module" warnings
    ignore? = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      Ecto.Migrator.run(repo, Ecto.Migrator.migrations_path(Chat.Repo), :up,
        all: true,
        log: false
      )
    after
      Code.put_compiler_option(:ignore_module_conflict, ignore?)
    end

    Sandbox.mode(repo, :manual)
  end

  defp assert_logical_wal!(admin) do
    case Db.wal_level(admin) do
      "logical" ->
        :ok

      level ->
        raise """
        :pg_pair tests need host PostgreSQL with wal_level=logical (got #{level}).
        Set `wal_level = logical` in postgresql.conf and restart PostgreSQL,
        or skip them with `mix test --exclude pg_pair`.
        """
    end
  end

  defp with_admin(fun), do: Db.with_conn(base_config(), "postgres", fun)

  defp base_config, do: UnitARepo.config()

  defp conninfo(repo) do
    repo.config()
    |> Keyword.put_new(:port, 5432)
    |> Keyword.take([:hostname, :port, :username, :password, :database])
    |> Enum.map_join(" ", fn {key, value} -> "#{@conninfo_keys[key]}=#{value}" end)
  end
end
