defmodule Chat.Storage.Role do
  @moduledoc """
  Storage unit roles: capabilities, on-disk dirs and role resolution from a mount.

  The role dir (`<mount>/<role>_db`) is the source of truth for a drive's role.
  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.3 and §7.1.
  """

  @type t :: :internal | :main | :backup | :cargo | :onliners
  @type capability :: :cub | :pg | :pq_files | :pipeline

  @dirs %{
    internal: "db",
    main: "main_db",
    backup: "backup_db",
    cargo: "cargo_db",
    onliners: "onliners_db"
  }
  # Decider's current order: the first present role dir wins
  @priority [:cargo, :onliners, :backup, :main]

  @doc """
  Resolves the role of a mounted USB drive.

  - `:blank` — no role dir on the drive
  - `{:ok, role}` — the highest-priority role dir present; legacy drives with
    several CubDB-only role dirs keep resolving by priority
  - `{:error, {:multiple_roles, roles}}` — more than one role dir has its own `pg/`
    cluster, so picking one by priority would orphan the others
  """
  @spec from_mount(Path.t()) :: {:ok, t()} | :blank | {:error, {:multiple_roles, [t()]}}
  def from_mount(mount_path) do
    present = @priority |> Enum.filter(&File.dir?(Path.join(mount_path, dir(&1))))
    with_pg = present |> Enum.filter(&File.dir?(Path.join([mount_path, dir(&1), "pg"])))

    case {present, with_pg} do
      {[], _} -> :blank
      {_, [_, _ | _]} -> {:error, {:multiple_roles, with_pg}}
      {[role | _], _} -> {:ok, role}
    end
  end

  @capabilities %{
    internal: [:cub, :pg, :pq_files, :pipeline],
    main: [:cub, :pg, :pq_files, :pipeline],
    backup: [:cub, :pg, :pq_files, :pipeline],
    cargo: [:cub],
    onliners: [:cub]
  }

  @spec capabilities(t()) :: [capability()]
  def capabilities(role), do: Map.fetch!(@capabilities, role)

  @spec dir(t()) :: String.t()
  def dir(role), do: Map.fetch!(@dirs, role)

  @spec all() :: [t()]
  def all, do: Map.keys(@dirs)
end
