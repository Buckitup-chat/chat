defmodule Chat.Db.QueueWriter do
  @moduledoc """
  Consumes the queue. Handles fsync and compaction?

  """
  require Logger
  require Record

  Record.defrecord(:w_state,
    db: nil,
    queue: nil,
    status_relay: nil,
    dry_run: false,
    dirt_count: 0,
    fsync_timer: nil,
    compacting: false,
    compaction_timer: nil
  )

  alias Chat.Db.Maintenance
  alias Chat.Db.WriteQueue

  @fsync_timout_s 1
  @fsync_trigger_count 10
  @compaction_timeout_m 7
  @dry_threshold_b 100 * 1024 * 1024

  def from_opts(opts) do
    w_state(
      db: opts |> Keyword.fetch!(:db),
      queue: opts |> Keyword.fetch!(:queue),
      status_relay: opts |> Keyword.fetch!(:status_relay)
    )
  end

  def fsync_needed?(w_state(dirt_count: count)), do: count > @fsync_trigger_count

  def demand_queue(w_state(queue: write_q) = state) do
    WriteQueue.demand(write_q)

    state
  end

  def start_compaction(w_state(db: db, dirt_count: 0, compacting: false, dry_run: false) = state) do
    "[db writer] compaction started" |> Logger.warn()
    CubDB.compact(db)

    state
    |> w_state(compacting: true, compaction_timer: nil)
  end

  def start_compaction(state), do: state

  def abort_compaction(w_state(compacting: false) = state), do: state

  def abort_compaction(w_state(db: db) = state) do
    "[db writer] compaction aborted" |> Logger.warn()
    CubDB.halt_compaction(db)

    state |> w_state(compacting: false)
  end

  def cancel_compaction_timer(w_state(compaction_timer: nil) = state), do: state

  def cancel_compaction_timer(w_state(compaction_timer: timer) = state) do
    Process.cancel_timer(timer)

    state |> w_state(compaction_timer: nil)
  end

  def cancel_fsync_timer(w_state(fsync_timer: nil) = state), do: state

  def cancel_fsync_timer(w_state(fsync_timer: timer) = state) do
    Process.cancel_timer(timer)

    state |> w_state(fsync_timer: nil)
  end

  def decide_if_dry(w_state(db: db) = state) do
    if Maintenance.db_free_space(db) < @dry_threshold_b do
      state
      |> cancel_fsync_timer
      |> cancel_compaction_timer
      |> abort_compaction
      |> w_state(dry_run: true)
      |> tap(fn _ ->
        "[db writer] decided read only" |> Logger.warn()
      end)
    else
      state
      |> w_state(dry_run: false)
      |> tap(fn _ ->
        "[db writer] decided writable" |> Logger.warn()
      end)
    end
    |> notify_relay()
  end

  def notify_relay(w_state(status_relay: relay, dry_run: status) = state) do
    Agent.update(relay, fn _ -> status end)

    state
  end

  def db_delete(w_state(dry_run: true) = state, _list), do: state

  def db_delete(w_state(db: db, dirt_count: old_count) = state, list) do
    CubDB.transaction(db, fn tx ->
      Enum.reduce(list, tx, fn
        {min, max}, tx when is_tuple(min) and is_tuple(max) ->
          CubDB.Tx.select(tx, min_key: min, max_key: max)
          |> Enum.map(fn {k, _} -> CubDB.Tx.delete(tx, k) end)

        key, tx ->
          CubDB.Tx.delete(tx, key)
      end)
      |> then(&{:commit, &1, :ok})
    end)

    state |> w_state(dirt_count: old_count + 1)
  end

  def db_write(w_state(dry_run: true) = state, _list), do: state

  def db_write(w_state(db: db, dirt_count: old_count) = state, list) do
    CubDB.transaction(db, fn tx ->
      Enum.reduce(list, tx, fn {key, value}, tx -> CubDB.Tx.put(tx, key, value) end)
      |> then(&{:commit, &1, :ok})
    end)

    case list do
      [{{:file_chunk, _, _, _}, _}] -> 1000
      _ -> Enum.count(list)
    end
    |> then(fn count ->
      state |> w_state(dirt_count: old_count + count)
    end)
  end

  def fsync(w_state(dry_run: true) = state), do: state

  def fsync(w_state(db: db) = state) do
    "[db writer] fsyncing" |> Logger.warn()
    CubDB.file_sync(db)

    state
    |> start_compaction_timer()
    |> w_state(dirt_count: 0)
  end

  def start_compaction_timer(w_state(compaction_timer: nil) = state) do
    state
    |> w_state(
      compaction_timer:
        Process.send_after(self(), :compact, :timer.minutes(@compaction_timeout_m))
    )
  end

  def start_compaction_timer(state), do: state

  def start_fsync_timer(w_state(fsync_timer: nil) = state) do
    state
    |> w_state(fsync_timer: Process.send_after(self(), :fsync, :timer.seconds(@fsync_timout_s)))
  end

  def start_fsync_timer(state), do: state
end
