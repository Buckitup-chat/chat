defmodule Chat.Storage.UnitAnnouncer do
  @moduledoc """
  Announces a storage unit being up, as the last child of its engine tree.

  On start it reads the unit's PG system identifier, registers the unit in
  `Chat.Storage.Units` and broadcasts `{:unit_up, unit}` on `"storage"`. On stop
  it unregisters and broadcasts `{:unit_down, unit}`.

  It also keeps broadcasting the legacy `{:chunk_pipeline, {:drive_mounted |
  :drive_unmounted, system_id}}` on `"chunk_pipeline"` until #802 moves the
  consumers to unit events. Callers that pass no `unit:` (platform drives, until
  #802) get the legacy events only.

  Returns `:ignore` when the system identifier can't be queried or the unit's
  role is already taken.

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.5.
  """

  use GenServer

  alias Chat.Storage.Pg
  alias Chat.Storage.Unit
  alias Chat.Storage.Units

  @topic "storage"
  @legacy_topic "chunk_pipeline"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl GenServer
  def init(opts) do
    unit = Keyword.get(opts, :unit)
    repo = Keyword.get_lazy(opts, :repo, fn -> unit && Unit.repo(unit) end)
    Process.flag(:trap_exit, true)

    with {:ok, system_id} <- query_system_id(repo),
         {:ok, unit} <- register(unit, system_id) do
      broadcast_legacy({:drive_mounted, system_id})
      broadcast(unit, :unit_up)
      {:ok, %{system_id: system_id, unit: unit}}
    else
      {:error, _reason} -> :ignore
    end
  end

  @impl GenServer
  def terminate(_reason, %{system_id: system_id, unit: unit}) do
    if unit, do: Units.unregister(unit)
    broadcast(unit, :unit_down)
    broadcast_legacy({:drive_unmounted, system_id})
    :ok
  end

  defp register(nil, _system_id), do: {:ok, nil}

  defp register(unit, system_id) do
    unit = %{unit | system_id: system_id}

    case Units.register(unit) do
      :ok -> {:ok, unit}
      {:error, reason} -> {:error, reason}
    end
  end

  defp query_system_id(repo) do
    case Pg.system_identifier(repo) do
      nil -> {:error, :no_system_id}
      system_id -> {:ok, system_id}
    end
  end

  defp broadcast(nil, _event), do: :ok
  defp broadcast(unit, event), do: Phoenix.PubSub.broadcast(Chat.PubSub, @topic, {event, unit})

  defp broadcast_legacy(event),
    do: Phoenix.PubSub.broadcast(Chat.PubSub, @legacy_topic, {:chunk_pipeline, event})
end
