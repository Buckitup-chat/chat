defmodule Chat.Storage.Units do
  @moduledoc """
  Registry of the storage units that are up.

  Backed by `Registry` with a unique key = role, so there is at most one unit per
  role (spec §2.4). The value is the `%Unit{}`. An entry belongs to the process
  that registered it (the unit's `UnitAnnouncer`) and disappears when that
  process stops.

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.5.
  """

  alias Chat.Storage.Role
  alias Chat.Storage.Unit

  @registry __MODULE__.Registry

  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: @registry)

  @doc """
  Registers `unit` under its role for the calling process.

  A taken role is refused. A unit with PG must carry its `system_id`.
  """
  @spec register(Unit.t()) :: :ok | {:error, {:already_registered, pid()} | :no_system_id}
  def register(%Unit{role: role} = unit) do
    with {:system_id, true} <- {:system_id, has_system_id?(unit)},
         {:ok, _owner} <- Registry.register(@registry, role, unit) do
      :ok
    else
      {:system_id, false} -> {:error, :no_system_id}
      {:error, {:already_registered, _pid}} = error -> error
    end
  end

  @spec unregister(Unit.t()) :: :ok
  def unregister(%Unit{role: role}), do: Registry.unregister(@registry, role)

  @spec by_role(Role.t()) :: {:ok, Unit.t()} | :error
  def by_role(role) do
    case Registry.lookup(@registry, role) do
      [{_pid, unit}] -> {:ok, unit}
      [] -> :error
    end
  end

  @spec by_id(Unit.id()) :: {:ok, Unit.t()} | :error
  def by_id(id), do: find(&(&1.id == id))

  @spec by_system_id(String.t()) :: {:ok, Unit.t()} | :error
  def by_system_id(system_id), do: find(&(&1.system_id == system_id))

  @spec list() :: [Unit.t()]
  def list, do: @registry |> Registry.select([{{:_, :_, :"$1"}, [], [:"$1"]}])

  @doc "Units that are up, except `unit` itself."
  @spec others(Unit.t()) :: [Unit.t()]
  def others(%Unit{role: role}), do: list() |> Enum.reject(&(&1.role == role))

  defp has_system_id?(unit), do: :pg not in Unit.capabilities(unit) or is_binary(unit.system_id)

  defp find(match?) do
    case list() |> Enum.find(match?) do
      nil -> :error
      unit -> {:ok, unit}
    end
  end
end
