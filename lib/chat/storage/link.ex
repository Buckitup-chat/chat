defmodule Chat.Storage.Link do
  @moduledoc """
  A directed data flow `from ~> to` between two storage units.

  A link carries all three layers at once (CubDB, PG rows, chunk blobs), so no
  scenario can move rows and forget their blobs. A layer applies when both units
  have the matching capability; CubDB also needs both databases to be running.

  - `bootstrap/1` — one-shot catch-up (`Chat.Storage.Link.Bootstrap`)
  - `replicate/1` — live follow (`Chat.Storage.Link.Replication`)
  - `await/3` — until `to` holds the blobs `from` provided (`Chat.Storage.Link.ChunkAwait`)
  - `stop/1` — tears down whatever `replicate/1` left, always on the `from` side

  A link never writes blobs: it tells `to` what is missing and where to get it, and
  `to`'s own chunk pipeline pulls the bytes. A link never switches Default.

  Status lives in `Chat.Storage.Links`.

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.7.
  """

  alias Chat.Storage.Link.Bootstrap
  alias Chat.Storage.Link.ChunkAwait
  alias Chat.Storage.Link.Filter
  alias Chat.Storage.Link.Replication
  alias Chat.Storage.Unit

  @enforce_keys [:from, :to]
  defstruct [:from, :to, filter: :all]

  @type t :: %__MODULE__{from: Unit.t(), to: Unit.t(), filter: :all | Filter.t()}
  @type id :: {Chat.Storage.Role.t(), Chat.Storage.Role.t()}
  @type layer :: :cub | :pg | :blobs

  @spec new(Unit.t(), Unit.t(), keyword()) :: t()
  def new(%Unit{} = from, %Unit{} = to, opts \\ []) do
    %__MODULE__{from: from, to: to, filter: Keyword.get(opts, :filter, :all)}
  end

  @doc "`from ~> to` builds a link with no filter. `import Chat.Storage.Link, only: [~>: 2]`."
  @spec Unit.t() ~> Unit.t() :: t()
  def from ~> to, do: new(from, to)

  @spec id(t()) :: id()
  def id(%__MODULE__{from: from, to: to}), do: {from.role, to.role}

  @doc """
  PG object names: the publication lives on `from` (`"internal_to_main"`); the
  subscription on `to` and its slot on `from` share one name (`"main_from_internal"`).
  """
  @spec name(t(), :publication | :subscription | :slot) :: String.t()
  def name(%__MODULE__{from: from, to: to}, kind) do
    case kind do
      :publication -> "#{from.role}_to_#{to.role}"
      kind when kind in [:subscription, :slot] -> "#{to.role}_from_#{from.role}"
    end
  end

  @doc "Layers this link moves, from the units' capabilities and running CubDBs."
  @spec layers(t()) :: [layer()]
  def layers(%__MODULE__{from: from, to: to} = link) do
    for {layer, true} <- [
          cub: both?(from, to, :cub) and cub_running?(from) and cub_running?(to),
          pg: both?(from, to, :pg),
          blobs: both?(from, to, :pq_files) and Filter.chunks?(link.filter)
        ],
        do: layer
  end

  defdelegate bootstrap(link), to: Bootstrap, as: :run
  defdelegate replicate(link), to: Replication, as: :start
  defdelegate stop(link), to: Replication
  defdelegate lag(link), to: Replication

  @doc """
  Waits until no `to` holds a `missing_chunks` row sourced from its link's `from`.

  Options: `:poll_ms` (1 s), `:stall_ms` (60 s without progress gives up).
  Returns `:ok` or `{:stalled, %{link_id => remaining}}`.
  """
  @spec await([t()], :chunks, keyword()) :: :ok | {:stalled, %{id() => pos_integer()}}
  def await(links, :chunks, opts \\ []), do: ChunkAwait.run(links, opts)

  defp both?(from, to, capability),
    do: capability in Unit.capabilities(from) and capability in Unit.capabilities(to)

  defp cub_running?(unit), do: unit |> Unit.cub_name() |> Process.whereis() |> is_pid()
end
