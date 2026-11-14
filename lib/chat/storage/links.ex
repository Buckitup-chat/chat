defmodule Chat.Storage.Links do
  @moduledoc """
  Status of every unit-to-unit link, keyed by `Chat.Storage.Link.id/1`.

  One place for the admin UI and LEDs to read what flows where:

      Links.list()
      #=> [%{id: {:main, :internal}, status: :replicating, lag_bytes: 1_204},
      #    %{id: {:internal, :backup}, status: {:bootstrapping, %{rows: :done}}, lag_bytes: nil}]

  Statuses: `:idle | {:bootstrapping, progress} | :replicating | {:awaiting, {done, total}} |
  :stopped | {:partial, map} | {:error, term}`.

  It also keeps the **replication source** of each receiving unit: the `system_id` of
  the unit that `Link.replicate/1` streams rows from. `ReplicationListener` on the
  receiving unit stamps it on `missing_chunks.source_drive_id` (spec §1.6, §2.7.1).

  Backed by a public ETS table owned by this process.

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.7.4.
  """

  use GenServer

  alias Chat.Storage.Link
  alias Chat.Storage.Role
  alias Chat.Storage.Unit

  @table __MODULE__

  @type status ::
          :idle
          | {:bootstrapping, map()}
          | :replicating
          | {:awaiting, {non_neg_integer(), non_neg_integer()}}
          | :stopped
          | {:partial, map()}
          | {:error, term()}
  @type entry :: %{id: Link.id(), status: status(), lag_bytes: non_neg_integer() | nil}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  # --- Status

  @spec put_status(Link.t() | Link.id(), status()) :: :ok
  def put_status(link, status) do
    id = link_id(link)

    lag_bytes =
      case status do
        :replicating -> lag_bytes(id)
        _ -> nil
      end

    :ets.insert(@table, {{:link, id}, %{id: id, status: status, lag_bytes: lag_bytes}})
    :ok
  end

  @spec put_lag(Link.t() | Link.id(), non_neg_integer()) :: :ok
  def put_lag(link, bytes) do
    id = link_id(link)

    case get(id) do
      {:ok, entry} -> :ets.insert(@table, {{:link, id}, %{entry | lag_bytes: bytes}})
      :error -> :ok
    end

    :ok
  end

  @spec status(Link.t() | Link.id()) :: status() | nil
  def status(link) do
    case link |> link_id() |> get() do
      {:ok, %{status: status}} -> status
      :error -> nil
    end
  end

  @spec get(Link.id()) :: {:ok, entry()} | :error
  def get(id) do
    case :ets.lookup(@table, {:link, id}) do
      [{_key, entry}] -> {:ok, entry}
      [] -> :error
    end
  end

  @spec list() :: [entry()]
  def list, do: :ets.select(@table, [{{{:link, :_}, :"$1"}, [], [:"$1"]}])

  @doc "Ids of the links currently replicating out of `role`."
  @spec replicating_from(Role.t()) :: [Link.id()]
  def replicating_from(role) do
    for %{id: {^role, _to} = id, status: :replicating} <- list(), do: id
  end

  @spec delete(Link.t() | Link.id()) :: :ok
  def delete(link) do
    :ets.delete(@table, {:link, link_id(link)})
    :ok
  end

  # --- Replication sources (receiving unit → system_id it replicates from)

  @spec register_source(Unit.t(), Unit.t()) :: :ok
  def register_source(%Unit{role: to_role}, %Unit{system_id: from_system_id}) do
    :ets.insert(@table, {{:source, to_role}, from_system_id})
    :ok
  end

  @doc "Forgets `from` as the source of `to`, unless another link has replaced it since."
  @spec unregister_source(Unit.t(), Unit.t()) :: :ok
  def unregister_source(%Unit{role: to_role}, %Unit{system_id: from_system_id}) do
    :ets.match_delete(@table, {{:source, to_role}, from_system_id})
    :ok
  end

  @doc "`system_id` the unit replicates rows from; `nil` when no link replicates into it."
  @spec replication_source(Unit.t()) :: String.t() | nil
  def replication_source(%Unit{role: role}) do
    case :ets.lookup(@table, {:source, role}) do
      [{_key, system_id}] -> system_id
      [] -> nil
    end
  end

  defp lag_bytes(id) do
    case get(id) do
      {:ok, %{lag_bytes: bytes}} -> bytes
      :error -> nil
    end
  end

  defp link_id(%Link{} = link), do: Link.id(link)
  defp link_id({_from, _to} = id), do: id
end
