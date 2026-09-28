defmodule Chat.NetworkSynchronization.Electric.ReadSessions do
  @moduledoc """
  Client side of peer read gating: per `{peer_url, shape}` Bearer tokens.

  Lazy — nothing is opened until a peer answers `401 read_session_required`,
  which happens only in the peer's `trust` mode. Concurrent opens of the same
  key share one request. Tokens live in memory only (ETS) and are renewed when
  less than 60 s remain.

  A failed open (`:not_in_trust_chain`, `:unknown_user`, …) surfaces as
  `{:error, {:read_session, reason}}`; callers retry on their own backoff,
  starting no sooner than `probe_after_ms/0` (awaiting approval).
  """

  use GenServer

  import Tools.GenServerHelpers

  alias Chat.NetworkSynchronization.Electric.ReadSessionClient

  # Server issues a fixed 5 min token (`Chat.Pq.ReadSession`), no refresh. We
  # stamp expiry on receipt, so our clock runs late by issue→receipt latency;
  # renewing with 1 min left absorbs that. The gate checks only at request
  # start, so an in-flight long poll outliving the token is fine.
  @renew_before_ms :timer.seconds(60)
  # An open is challenge GET + session POST, 10 s receive timeout each
  # (`ReadSessionClient`). Must stay under the server challenge TTL (60 s,
  # `Chat.Challenge`).
  @open_timeout :timer.seconds(30)
  # Backoff floor while the peer refuses us (`not_in_trust_chain`, …). Clearing
  # that needs a human to vouch, so fast retries only burn peer challenges and
  # logs; 15 s keeps approval pickup quick.
  @probe_after_ms :timer.seconds(15)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  def probe_after_ms, do: @probe_after_ms

  @doc """
  Calls `request_fun.(headers)` with the current Bearer header (if any). On
  `401 read_session_required` opens a session and calls it once more.
  """
  def request(peer_url, shape, request_fun, server \\ __MODULE__) do
    peer_url
    |> headers(shape, server)
    |> request_fun.()
    |> case do
      {:ok, %{status: 401, body: %{"error" => "read_session_required"}}} ->
        open_and_request(peer_url, shape, request_fun, server)

      result ->
        result
    end
  end

  defp open_and_request(peer_url, shape, request_fun, server) do
    case open(peer_url, shape, server) do
      :ok -> peer_url |> headers(shape, server) |> request_fun.()
      {:error, reason} -> {:error, {:read_session, reason}}
    end
  end

  @doc "Bearer header for the session of `shape` on `peer_url`, `[]` when none is open."
  def headers(peer_url, shape, server \\ __MODULE__) do
    case :ets.lookup(server, {peer_url, shape}) do
      [] ->
        []

      [{_key, token, expires_at}] ->
        if expires_at - now() > @renew_before_ms,
          do: bearer(token),
          else: renewed_headers(peer_url, shape, server)
    end
  end

  defp renewed_headers(peer_url, shape, server) do
    with :ok <- open(peer_url, shape, server),
         [{_key, token, _expires_at}] <- :ets.lookup(server, {peer_url, shape}) do
      bearer(token)
    else
      _ -> []
    end
  end

  @doc "Opens (or renews) the session. Returns `:ok` or `{:error, reason}`."
  def open(peer_url, shape, server \\ __MODULE__) do
    GenServer.call(server, {:open, {peer_url, shape}}, @open_timeout)
  end

  @doc "Extracts the read-session failure from a stream exit reason, `nil` for other exits."
  def blocked_by({%Electric.Client.Error{resp: {:read_session, reason}}, _stacktrace}),
    do: reason

  def blocked_by(_exit_reason), do: nil

  ## GenServer

  @impl true
  def init(opts) do
    table = Keyword.fetch!(opts, :name)
    :ets.new(table, [:set, :public, :named_table, read_concurrency: true])

    %{
      table: table,
      opener: Keyword.get(opts, :opener, &ReadSessionClient.open/2),
      waiting: %{},
      refs: %{}
    }
    |> ok()
  end

  @impl true
  def handle_call({:open, key}, from, %{waiting: waiting} = state) do
    case Map.fetch(waiting, key) do
      {:ok, froms} -> %{state | waiting: Map.put(waiting, key, [from | froms])}
      :error -> state |> start_open(key) |> Map.update!(:waiting, &Map.put(&1, key, [from]))
    end
    |> noreply()
  end

  defp start_open(%{opener: opener, refs: refs} = state, {peer_url, shape} = key) do
    %{ref: ref} =
      Task.Supervisor.async_nolink(Chat.TaskSupervisor, fn -> opener.(peer_url, shape) end)

    %{state | refs: Map.put(refs, ref, key)}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    state |> finish_open(ref, result) |> noreply()
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    state |> finish_open(ref, {:error, {:open_crashed, reason}}) |> noreply()
  end

  defp finish_open(%{table: table, refs: refs, waiting: waiting} = state, ref, result) do
    {key, refs} = Map.pop(refs, ref)
    {froms, waiting} = Map.pop(waiting, key, [])

    reply =
      case result do
        {:ok, token, expires_in} ->
          :ets.select_delete(table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now()}], [true]}])
          :ets.insert(table, {key, token, now() + :timer.seconds(expires_in)})
          :ok

        {:error, _} = error ->
          :ets.delete(table, key)
          error
      end

    Enum.each(froms, &GenServer.reply(&1, reply))
    %{state | refs: refs, waiting: waiting}
  end

  defp bearer(token), do: [{"authorization", "Bearer " <> token}]

  defp now, do: System.monotonic_time(:millisecond)
end
