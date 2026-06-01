defmodule Chat.Upload.IngestThrottle do
  @moduledoc """
  Admission control for heavy file-chunk ingest writes.

  The device's PostgreSQL handles a single ~4 MB chunk INSERT in ~1 ms, but
  concurrent chunk uploads still contend for the shared connection pool and the
  request-processing hot path. To keep the interactive workload (LiveView,
  auth, shape reads) responsive, only a fraction of the pool may be busy with
  chunk writes at once.

  This is a counting semaphore: it hands out up to `limit` tokens, defaulting to
  `max(1, div(pool_size, 3))` so it auto-scales with `POOL_SIZE`. A token is
  bound to the **caller process** via a monitor, so it is released even if the
  request process crashes mid-write — no leaks, no manual cleanup on the error
  path. Callers that find no token free get `{:busy, retry_after_seconds}` and
  should return `429 Too Many Requests` with a `Retry-After` header.

  Acquire with `checkout/0`, release with `checkin/0` (typically from a
  `Plug.Conn.register_before_send/2` callback). See
  `ChatWeb.Plugs.ElectricIngestThrottle`.
  """

  use GenServer

  @default_retry_after_seconds 2

  ## Client API

  def start_link(opts) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    name = Keyword.get(gen_opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Try to acquire a token for the calling process.

  Returns `:ok` if a token was granted (released automatically when the caller
  exits, or explicitly via `checkin/0`), or `{:busy, retry_after_seconds}` when
  all tokens are in use.
  """
  @spec checkout(GenServer.server()) :: :ok | {:busy, pos_integer()}
  def checkout(server \\ __MODULE__) do
    GenServer.call(server, {:checkout, self()})
  end

  @doc "Release the token held by the calling process."
  @spec checkin(GenServer.server()) :: :ok
  def checkin(server \\ __MODULE__) do
    GenServer.cast(server, {:checkin, self()})
  end

  @doc "Current number of tokens in use (for tests / introspection)."
  @spec in_use(GenServer.server()) :: non_neg_integer()
  def in_use(server \\ __MODULE__) do
    GenServer.call(server, :in_use)
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    limit = Keyword.get_lazy(opts, :limit, &default_limit/0)
    retry_after = Keyword.get(opts, :retry_after_seconds, @default_retry_after_seconds)

    {:ok, %{limit: limit, retry_after: retry_after, holders: %{}}}
  end

  @impl true
  def handle_call({:checkout, pid}, _from, state) do
    cond do
      Map.has_key?(state.holders, pid) ->
        # Already holding a token (idempotent) — don't double-count.
        {:reply, :ok, state}

      map_size(state.holders) < state.limit ->
        ref = Process.monitor(pid)
        {:reply, :ok, put_in(state.holders[pid], ref)}

      true ->
        {:reply, {:busy, state.retry_after}, state}
    end
  end

  def handle_call(:in_use, _from, state) do
    {:reply, map_size(state.holders), state}
  end

  @impl true
  def handle_cast({:checkin, pid}, state) do
    {:noreply, release(state, pid)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, release(state, pid, :already_demonitored)}
  end

  ## Helpers

  defp release(state, pid, demonitor \\ :demonitor) do
    case Map.pop(state.holders, pid) do
      {nil, _holders} ->
        state

      {ref, holders} ->
        if demonitor == :demonitor, do: Process.demonitor(ref, [:flush])
        %{state | holders: holders}
    end
  end

  defp default_limit do
    repo = Chat.Db.repo()
    pool_size = get_in(Application.get_env(:chat, repo) || [], [:pool_size]) || 10
    max(1, div(pool_size, 3))
  end
end
