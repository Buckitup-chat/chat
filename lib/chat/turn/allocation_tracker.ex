defmodule Chat.Turn.AllocationTracker do
  @moduledoc """
  Counts live TURN allocations per credential and per client IP.

  stun ignores `turn_max_allocations`, so the limits are enforced here:

    * `Chat.Turn.Auth` answers a credential at its limit as expired — stun then
      refuses new allocations for it while its live ones keep refreshing;
    * the `turn_session_start` hook stops an allocation that is beyond a limit
      (one that raced past the auth check, or one beyond the client IP limit).

  The global cap is the relay port range of `Chat.Turn.Listener`.
  """

  use GenServer

  @table __MODULE__
  @max_per_user 4
  @max_per_ip 32

  def max_per_user, do: @max_per_user
  def max_per_ip, do: @max_per_ip

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @doc "Whether `user` holds as many live allocations as allowed"
  @spec user_at_limit?(binary()) :: boolean()
  def user_at_limit?(user), do: count({:user, user}) >= @max_per_user

  @spec count({:user, binary()} | {:ip, :inet.ip_address()}) :: non_neg_integer()
  def count(key) do
    case :ets.lookup(@table, key) do
      [{^key, n}] -> n
      [] -> 0
    end
  end

  @doc "stun `hook_fun`. Runs inside the allocation process on `turn_session_start`"
  def hook(:turn_session_start, %{user: user, client: {ip, _port}}) do
    case track(self(), user, ip) do
      :ok -> :ok
      :over_limit -> :turn.stop(self())
    end
  end

  def hook(_name, _info), do: :ok

  @doc "Counts `pid` as a live allocation until it exits"
  @spec track(pid(), binary(), :inet.ip_address()) :: :ok | :over_limit
  def track(pid, user, ip), do: GenServer.call(__MODULE__, {:track, pid, user, ip})

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:track, pid, user, ip}, _from, refs) do
    ref = Process.monitor(pid)
    user_count = increment({:user, user})
    ip_count = increment({:ip, ip})

    reply =
      if user_count > @max_per_user or ip_count > @max_per_ip, do: :over_limit, else: :ok

    {:reply, reply, Map.put(refs, ref, {user, ip})}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, refs) do
    {{user, ip}, refs} = Map.pop!(refs, ref)
    decrement({:user, user})
    decrement({:ip, ip})

    {:noreply, refs}
  end

  defp increment(key), do: :ets.update_counter(@table, key, 1, {key, 0})

  defp decrement(key) do
    case :ets.update_counter(@table, key, -1) do
      0 -> :ets.delete(@table, key)
      _ -> true
    end
  end
end
