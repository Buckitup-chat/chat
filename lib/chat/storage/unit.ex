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

  PG paths are always derived; whether a PG cluster is actually started there is
  the caller's (platform's) decision.

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.1–2.2.
  """

  alias Chat.Storage.Role

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

  @pg_base_port 5432
  @pg_run_dir "/tmp/pg_run"
  @drives_registry Platform.Drives.Registry
  # Same names BootSupervisor defines at runtime; built at compile time to avoid runtime atoms
  @usb_repos Map.new(?a..?z, &{&1, Module.concat([Platform.Dev, :"Sd#{<<&1>>}", Repo])})
  @cub_names %{
    internal: Chat.Db.InternalDb,
    main: Chat.Db.MainDb,
    backup: Chat.Db.BackupDb,
    cargo: Chat.Db.CargoDb,
    onliners: Chat.Db.OnlinersDb
  }

  @spec internal() :: t()
  def internal, do: %__MODULE__{id: :internal, role: :internal, root: config(:internal_root)}

  @spec usb(String.t(), Role.t()) :: t()
  def usb(device, role) when is_binary(device) and role != :internal do
    %__MODULE__{id: device, role: role, root: Path.join(config(:media_root), device)}
  end

  @spec path(t(), resource()) :: Path.t()
  def path(%__MODULE__{} = unit, resource),
    do: [unit.root, role_dir(unit), segment(resource)] |> Path.join()

  @spec role_dir(t()) :: String.t()
  def role_dir(%__MODULE__{role: role}), do: Role.dir(role)

  @spec pg_port(t()) :: pos_integer()
  def pg_port(%__MODULE__{id: :internal}), do: @pg_base_port
  def pg_port(%__MODULE__{id: "sd" <> <<letter, _::binary>>}), do: @pg_base_port + 1 + letter - ?a

  @spec pg_run(t()) :: Path.t()
  def pg_run(%__MODULE__{id: id}), do: Path.join(@pg_run_dir, to_string(id))

  @spec repo(t()) :: module()
  def repo(%__MODULE__{id: :internal}), do: Chat.Repo

  def repo(%__MODULE__{id: "sd" <> <<letter, _::binary>>}), do: Map.fetch!(@usb_repos, letter)

  @spec cub_name(t()) :: module()
  def cub_name(%__MODULE__{role: role}), do: Map.fetch!(@cub_names, role)

  @spec via(t(), atom()) :: {:via, Registry, {module(), {atom(), id()}}}
  def via(%__MODULE__{id: id}, component),
    do: {:via, Registry, {@drives_registry, {component, id}}}

  @spec capabilities(t()) :: [Role.capability()]
  def capabilities(%__MODULE__{role: role}), do: Role.capabilities(role)

  defp segment(:cub_db), do: Chat.Db.version_path()
  defp segment(:cub_files), do: Chat.Db.version_path() <> "_files"
  defp segment(:pg), do: "pg"
  defp segment(:pq_files), do: "pq_files"
  defp segment(:electric), do: "electric"

  defp config(key), do: Application.fetch_env!(:chat, Chat.Storage) |> Keyword.fetch!(key)
end
