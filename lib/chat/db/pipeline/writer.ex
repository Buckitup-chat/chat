defmodule Chat.Db.Pipeline.Writer do
  @moduledoc """
  Consumes the queue. Handles fsync and FS write for files

  """
  require Logger
  require Record

  Record.defrecord(:w_state,
    db: nil,
    file_path: nil,
    queue: nil,
    compactor: nil,
    dirt_count: 0,
    fsync_timer: nil
  )

  alias Chat.Db.ChangeTracker
  alias Chat.Db.Pipeline.Compactor
  alias Chat.Db.WriteQueue, as: Queue

  alias Chat.FileFs

  @fsync_timeout_s 1
  @fsync_trigger_count 10

  def write(proc, list), do: GenServer.cast(proc, {:write, list})
  def delete(proc, list), do: GenServer.cast(proc, {:delete, list})

  def from_opts(opts) do
    w_state(
      db: opts |> Keyword.fetch!(:db),
      file_path: opts |> Keyword.fetch!(:files_path),
      queue: opts |> Keyword.fetch!(:queue),
      compactor: opts |> Keyword.fetch!(:compactor)
    )
  end

  def demand_queue(w_state(queue: write_q) = state) do
    Queue.demand(write_q)
    state
  end

  def notify_compactor(w_state(compactor: compactor) = state) do
    Compactor.activity(compactor)
    state
  end

  def db_delete(w_state(db: db, file_path: path, dirt_count: old_count) = state, list) do
    reducer = fn
      {{:file_chunk, key, _, _}, {:file_chunk, key, _, _}}, tx ->
        FileFs.delete_file(key, path)
        tx

      {min, max}, tx when is_tuple(min) and is_tuple(max) ->
        CubDB.Tx.select(tx, min_key: min, max_key: max)
        |> Enum.reduce(tx, fn {k, _}, tx -> CubDB.Tx.delete(tx, k) end)

      {:file_chunk, key, _, _}, tx ->
        FileFs.delete_file(key, path)
        tx

      key, tx ->
        CubDB.Tx.delete(tx, key)
    end

    CubDB.transaction(db, fn tx ->
      Enum.reduce(list, tx, reducer)
      |> then(&{:commit, &1, :ok})
    end)

    state |> w_state(dirt_count: old_count + 1)
  end

  def db_write(w_state(db: db, file_path: path, dirt_count: old_count) = state, list) do
    {chunks, db_items} = Enum.split_with(list, &match?({{:file_chunk, _, _, _}, _}, &1))

    CubDB.transaction(db, fn tx ->
      Enum.reduce(db_items, {tx, []}, fn {key, value}, {tx, acc} ->
        {CubDB.Tx.put(tx, key, value), [key | acc]}
      end)
      |> then(fn {tx, keys} -> {:commit, tx, keys} end)
    end)
    |> ChangeTracker.set_written()

    chunks
    |> Enum.each(fn {{:file_chunk, chunk_key, min, max} = key, data} ->
      FileFs.write_file(data, {chunk_key, min, max}, path)

      ChangeTracker.set_written([key])
    end)

    state |> w_state(dirt_count: old_count + Enum.count(db_items))
  end

  def start_fsync_timer(w_state(fsync_timer: nil) = state) do
    state
    |> w_state(fsync_timer: Process.send_after(self(), :fsync, :timer.seconds(@fsync_timeout_s)))
  end

  def start_fsync_timer(state), do: state

  def cancel_fsync_timer(w_state(fsync_timer: nil) = state), do: state

  def cancel_fsync_timer(w_state(fsync_timer: timer) = state) do
    Process.cancel_timer(timer)

    state |> w_state(fsync_timer: nil)
  end

  def fsync_needed?(w_state(dirt_count: count)), do: count > @fsync_trigger_count

  def fsync(w_state(db: db) = state) do
    ["[db writer] ", "fsyncing ", inspect(db)] |> Logger.warn()
    CubDB.file_sync(db)

    state |> w_state(dirt_count: 0)
  end
end
