defmodule Chat.Db.ChangeTracker do
  @moduledoc """
  Awaits for keys to get written in DB.

  Consider other opltions of communications

  Keeps a list of keys to check and actions to perform on key found in DB or timed out (after @timeout)
  Runs callbacks for `promise` and responses to calls for `await`
  """
  import Tools.GenServerHelpers

  use GenServer
  alias Chat.Db
  alias Chat.Db.ChangeTracker.Tracking

  @timeout :timer.seconds(Application.compile_env!(:chat, [__MODULE__, :expire_seconds]))
  @check_delay :timer.seconds(1)

  def ensure(opts) do
    key = Keyword.fetch!(opts, :writes_key)
    action = Keyword.fetch!(opts, :action)

    task = Task.async(fn -> await(key) end)
    action.()
    task |> Task.await(:infinity)
  end

  def await do
    key = {:change_tracking_marker, UUID.uuid4()}

    ensure(
      action: fn ->
        Db.put(key, true)
      end,
      writes_key: key
    )

    Db.delete(key)
  end

  def await(key) do
    __MODULE__
    |> GenServer.call({:await, key, expires(@timeout)}, 2 * @timeout)
  end

  def await_many(keys, timeout) do
    keys
    |> Enum.map(fn key ->
      Task.Supervisor.async(Chat.Db.ChangeTracker.Tasks, fn ->
        GenServer.call(__MODULE__, {:await, key, expires(timeout)}, 2 * timeout)
      end)
    end)
    |> Task.await_many(timeout)
  end

  def on_saved(action) do
    key = {:change_tracking_marker, UUID.uuid4()}

    Db.put(key, true)

    promise(
      key,
      fn ->
        action.()
        Db.delete(key)
      end,
      fn -> Db.delete(key) end
    )
  end

  def promise(key, success_fn, error_fn \\ fn -> :noop end) do
    __MODULE__
    |> GenServer.cast({:promise, key, success_fn, error_fn, expires(@timeout)})
  end

  def set_written(keys) do
    __MODULE__
    |> GenServer.cast({:written, keys})
  end

  # Implementation

  def start_link(_) do
    GenServer.start_link(__MODULE__, Tracking.new(), name: __MODULE__)
  end

  @impl true
  def init(opts) do
    schedule_timer(@check_delay)
    ok(opts)
  end

  @impl true
  def handle_call({:await, key, expiration}, from, state) do
    state
    |> Tracking.add_await(key, from, expiration)
    |> noreply()
  end

  @impl true
  def handle_cast({:promise, key, ok_fn, error_fn, expiration}, state) do
    state
    |> Tracking.add_promise(key, {ok_fn, error_fn}, expiration)
    |> noreply()
  end

  def handle_cast({:written, keys}, state) do
    state
    |> Tracking.check_written(now(), keys)
    |> noreply()
  end

  @impl true
  def handle_info(:tick, state) do
    state
    |> Tracking.check_written(now())
    |> tap(fn _ -> schedule_timer(@check_delay) end)
    |> noreply()
  end

  defp schedule_timer(delay) do
    Process.send_after(self(), :tick, delay)
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp expires(time), do: now() + time
end
