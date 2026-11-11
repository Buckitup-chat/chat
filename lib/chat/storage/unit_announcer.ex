defmodule Chat.Storage.UnitAnnouncer do
  @moduledoc """
  Announces a storage unit being up, as the last child of its engine tree.

  On start it registers the unit in `Chat.Storage.Units` and broadcasts
  `{:unit_up, unit}` on `"storage"`. On stop it unregisters and broadcasts
  `{:unit_down, unit}`.

  The unit's PG system id is taken from the unit when set (the chunk pipeline
  fills it), otherwise read from `Unit.repo/1`.

  Returns `:ignore` when there is no system id or the unit's role is already taken.

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.5.
  """

  use GenServer

  alias Chat.Storage.Pg
  alias Chat.Storage.Unit
  alias Chat.Storage.Units

  @topic "storage"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl GenServer
  def init(opts) do
    %Unit{} = unit = Keyword.fetch!(opts, :unit)
    Process.flag(:trap_exit, true)

    with {:ok, unit} <- with_system_id(unit),
         :ok <- Units.register(unit) do
      broadcast(unit, :unit_up)
      {:ok, unit}
    else
      {:error, _reason} -> :ignore
    end
  end

  @impl GenServer
  def terminate(_reason, unit) do
    Units.unregister(unit)
    broadcast(unit, :unit_down)
    :ok
  end

  defp with_system_id(%Unit{system_id: nil} = unit) do
    case unit |> Unit.repo() |> Pg.system_identifier() do
      nil -> {:error, :no_system_id}
      system_id -> {:ok, %{unit | system_id: system_id}}
    end
  end

  defp with_system_id(unit), do: {:ok, unit}

  defp broadcast(unit, event), do: Phoenix.PubSub.broadcast(Chat.PubSub, @topic, {event, unit})
end
