defmodule Chat.Storage.Unit do
  @moduledoc """
  A Storage Unit is one `(drive, role)` cluster: the internal storage, or a USB
  drive in its role.

  Every facet (paths, PG port and run dir, repo, CubDB name, registry names) is a
  pure derivation of the struct. This module is the only place that knows path
  segments and naming conventions.

  Layout under `<root>/<role_dir>/`:

      v.10.1/        :cub_db     CubDB generation, versioned
      v.10.1_files/  :cub_files  FileFs, versioned
      pg/            :pg         PG cluster, not versioned
      pq_files/      :pq_files   chunk blobs, not versioned
      electric/      :electric   Electric shape cache (Default unit only)

  The internal role dir is `"db"`; `config :chat, Chat.Storage, internal_dir: ...`
  overrides it to keep legacy locations (`priv/data` standalone, `priv/test_db` in tests).

  PG paths are always derived; whether a PG cluster is actually started there is
  the caller's (platform's) decision.

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.1–2.2.
  """

  alias Chat.Storage.Role

  # CubDB generation; bumping it starts a fresh CubDB next to the old one
  @cub_version "v.10.1"

  @enforce_keys [:id, :role, :root]
  defstruct [:id, :role, :root, :system_id]

  @type id :: :internal | String.t()
  @type resource :: :cub_db | :cub_files | :pg | :pq_files | :electric
  @type t :: %__MODULE__{
          id: id(),
          role: Role.t(),
          root: Path.t(),
          system_id: String.t() | nil
        }

  # --- Units: the internal storage, or a USB drive in a non-internal role

  @spec internal() :: t()
  def internal, do: %__MODULE__{id: :internal, role: :internal, root: config(:internal_root)}

  @spec usb(String.t(), Role.t()) :: t()
  def usb(device, role) when is_binary(device) and role != :internal,
    do: %__MODULE__{id: device, role: role, root: root(device)}

  @doc """
  Root of a unit, or the mount target of a USB device whose role is not known yet.
  """
  @spec root(t() | String.t()) :: Path.t()
  def root(%__MODULE__{root: root}), do: root
  def root(device) when is_binary(device), do: config(:media_root) |> Path.join(device)

  # --- Disk layout: `<root>/<role_dir>/<segment>`, the only place segments are known

  @spec path(t(), resource()) :: Path.t()
  def path(%__MODULE__{} = unit, resource) do
    segment =
      case resource do
        :cub_db -> @cub_version
        :cub_files -> @cub_version |> cub_files_dir()
        :pg -> "pg"
        :pq_files -> "pq_files"
        :electric -> "electric"
      end

    [unit.root, role_dir(unit), segment] |> Path.join()
  end

  @doc "CubDB generation dir name, e.g. `\"v.10.1\"`."
  @spec cub_version() :: String.t()
  def cub_version, do: @cub_version

  @doc """
  FileFs dir that sits next to a CubDB data dir. For running databases whose
  unit is not at hand (`CubDB.data_dir/1`).
  """
  @spec cub_files_dir(Path.t()) :: Path.t()
  def cub_files_dir(cub_db_dir), do: cub_db_dir <> "_files"

  # `internal_dir` keeps legacy internal locations (`priv/test_db`, `priv/data`)
  @spec role_dir(t()) :: String.t()
  def role_dir(%__MODULE__{role: role}) do
    case role do
      :internal -> Keyword.get(storage_config(), :internal_dir, Role.dir(:internal))
      role -> Role.dir(role)
    end
  end

  @spec capabilities(t()) :: [Role.capability()]
  def capabilities(%__MODULE__{role: role}), do: Role.capabilities(role)

  # --- PostgreSQL: internal on the base port, `sdX` on base + 1 + letter offset

  @pg_base_port 5432
  @pg_run_dir "/tmp/pg_run"

  @spec pg_port(t()) :: pos_integer()
  def pg_port(%__MODULE__{id: id}) do
    case id do
      :internal -> @pg_base_port
      "sd" <> <<letter, _::binary>> -> @pg_base_port + 1 + letter - ?a
    end
  end

  @spec pg_run(t()) :: Path.t()
  def pg_run(%__MODULE__{id: id}), do: Path.join(@pg_run_dir, to_string(id))

  # Same names BootSupervisor defines at runtime; built at compile time to avoid runtime atoms
  @usb_repos Map.new(?a..?z, &{&1, Module.concat([Platform.Dev, :"Sd#{<<&1>>}", Repo])})

  @doc """
  Repo of the unit's PG. `config :chat, Chat.Storage, repos: %{id => repo}` pins a
  repo per unit id (tests run units on `Chat.Test.UnitARepo` / `UnitBRepo`).
  """
  @spec repo(t()) :: module()
  def repo(%__MODULE__{id: id}) do
    case {storage_config() |> Keyword.get(:repos, %{}) |> Map.get(id), id} do
      {repo, _id} when repo != nil -> repo
      {nil, :internal} -> Chat.Repo
      {nil, "sd" <> <<letter, _::binary>>} -> Map.fetch!(@usb_repos, letter)
    end
  end

  # --- Process names

  @cub_names %{
    internal: Chat.Db.InternalDb,
    main: Chat.Db.MainDb,
    backup: Chat.Db.BackupDb,
    cargo: Chat.Db.CargoDb,
    onliners: Chat.Db.OnlinersDb
  }
  @drives_registry Platform.Drives.Registry

  @spec cub_name(t() | Role.t()) :: module()
  def cub_name(%__MODULE__{role: role}), do: cub_name(role)
  def cub_name(role) when is_atom(role), do: Map.fetch!(@cub_names, role)

  @spec via(t(), atom()) :: {:via, Registry, {module(), {atom(), id()}}}
  def via(%__MODULE__{id: id}, component),
    do: {:via, Registry, {@drives_registry, {component, id}}}

  defp config(key), do: storage_config() |> Keyword.fetch!(key)
  defp storage_config, do: Application.fetch_env!(:chat, Chat.Storage)
end
