defmodule Chat.Storage.Default.Electric do
  @moduledoc """
  The Electric stack of the Default unit (absorbs the former `PhoenixSyncReinit`).

  Electric's PG state (`electric_slot_default`, `electric_publication_default`)
  and its shape cache (`Unit.path(unit, :electric)`) exist only on the Default
  unit (spec §2.2, §2.6). `Chat.Storage.Default.switch_to/1` drives the steps.

  `Phoenix.Sync.Application.children/0` reads the whole `:phoenix_sync` env, so
  `:repo`, `:connection_opts` and `:storage_dir` are put there before the stack
  starts; `plug_opts/0` reads the same env.

  PG-side steps run only in `:embedded` mode; the `:sandbox` mode (tests) has
  no slot or publication.
  """

  use Toolbox.OriginLog

  alias Chat.Storage.Pg.LogicalReplicator
  alias Chat.Storage.Unit

  @slot "electric_slot_default"
  @publication "electric_publication_default"
  @supervisor Phoenix.Sync.Supervisor
  @stack Electric.StackSupervisor

  def slot, do: @slot
  def publication, do: @publication

  @doc "Stops the Electric stack, if it runs."
  @spec stop() :: :ok
  def stop do
    case Process.whereis(@stack) do
      nil ->
        :ok

      pid ->
        case Supervisor.terminate_child(@supervisor, @stack) do
          :ok -> :ok
          {:error, :not_found} -> Supervisor.stop(pid, :normal)
        end
    end

    # The child spec may exist even if the process is not running (failed at boot)
    _ = Supervisor.delete_child(@supervisor, @stack)
    :ok
  catch
    kind, error ->
      log("stopping Electric stack failed: #{kind} #{inspect(error)}", :warning)
      :ok
  end

  @doc """
  Drops Electric's PG state and cache on a unit it leaves. Skipped when the unit's
  repo is gone (ejected): its PG generates no WAL, and the leftovers are cleaned
  the next time it becomes Default.
  """
  @spec release(Unit.t()) :: :ok
  def release(%Unit{} = unit) do
    repo = Unit.repo(unit)

    if embedded?() and Chat.Db.repo_ready?(repo) do
      release_pg(repo)
      unit |> Unit.path(:electric) |> File.rm_rf()
    end

    :ok
  end

  @doc "Drops `electric_slot_default` and `electric_publication_default` on `repo`."
  @spec release_pg(module()) :: :ok
  def release_pg(repo) do
    # The walsender may still hold the slot right after the stack stopped
    _ =
      repo.query(
        "SELECT pg_terminate_backend(active_pid) FROM pg_replication_slots " <>
          "WHERE slot_name = $1 AND active_pid IS NOT NULL",
        [@slot]
      )

    _ =
      repo.query(
        "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name = $1",
        [@slot]
      )

    _ = repo.query("DROP PUBLICATION IF EXISTS #{@publication}", [])
    :ok
  end

  @doc "Ensures the Electric slot on `unit`'s PG, then starts the stack against it."
  @spec start(Unit.t()) :: :ok | {:error, term()}
  def start(%Unit{} = unit) do
    repo = Unit.repo(unit)

    with :ok <- ensure_slot(repo) do
      configure(repo, Unit.path(unit, :electric))
      start_stack()
    end
    |> tap(fn
      :ok -> log("Electric started on #{inspect(unit.id)}", :info)
      error -> log("Electric start on #{inspect(unit.id)} failed: #{inspect(error)}", :error)
    end)
  end

  @doc "Ensures `electric_slot_default` exists on `repo` (`:embedded` mode only)."
  @spec ensure_slot(module()) :: :ok | {:error, term()}
  def ensure_slot(repo) do
    if embedded?(),
      do: LogicalReplicator.ensure_slot_on_source(repo, @slot),
      else: :ok
  end

  defp configure(repo, storage_dir) do
    [repo: repo, connection_opts: connection_opts(repo), storage_dir: storage_dir]
    |> Enum.each(fn {key, value} -> Application.put_env(:phoenix_sync, key, value) end)
  end

  # Runtime opts of the running repo: they carry the dynamic port set at start
  defp connection_opts(repo) do
    %{opts: source} = Ecto.Adapter.lookup_meta(repo)

    [
      hostname: Keyword.get(source, :hostname, "localhost"),
      port: Keyword.get(source, :port, 5432),
      database: Keyword.get(source, :database),
      username: Keyword.get(source, :username),
      password: Keyword.get(source, :password),
      socket_options: [{:keepalive, true}]
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp start_stack do
    with {:ok, children} <- Phoenix.Sync.Application.children() do
      Enum.reduce_while(children, :ok, fn child, :ok -> child |> start_child() |> continue?() end)
    end
  end

  defp continue?(:ok), do: {:cont, :ok}
  defp continue?(error), do: {:halt, error}

  defp start_child(child) do
    case Supervisor.start_child(@supervisor, child) do
      {:ok, _pid} ->
        :ok

      {:ok, _pid, _info} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, :already_present} ->
        _ = Supervisor.delete_child(@supervisor, child_id(child))
        start_child(child)

      {:error, _reason} = error ->
        error
    end
  end

  defp child_id(%{id: id}), do: id
  defp child_id({module, _opts}), do: module
  defp child_id(module) when is_atom(module), do: module

  defp embedded?, do: Application.get_env(:phoenix_sync, :mode) == :embedded
end
