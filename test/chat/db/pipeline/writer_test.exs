defmodule Chat.Db.Pipeline.WriterTest do
  use ExUnit.Case, async: true

  import Chat.Db.Pipeline.Writer

  alias Chat.Db.Pipeline.Compactor
  alias Chat.Db.Pipeline.Writer
  alias Chat.Db.Pipeline.WriterProcess
  alias Chat.Db.WriteQueue
  alias Chat.FileFs

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    db = start_supervised!({CubDB, data_dir: Path.join(dir, "db")})
    files_path = Path.join(dir, "files")
    File.mkdir_p!(files_path)

    %{db: db, files_path: files_path}
  end

  test "deletes key ranges, single keys and file chunks", context do
    state = writer_state(context)
    chunk = {:file_chunk, "chunk-key", 0, 2}
    FileFs.write_file("abc", {"chunk-key", 0, 2}, context.files_path)

    state
    |> db_write([{{:range, 1}, 1}, {{:range, 2}, 2}, {:single, 3}, {:kept, 4}])
    |> db_delete([{{:range, 0}, {:range, 9}}, :single, {chunk, chunk}])
    |> db_delete([chunk])

    assert [{:kept, 4}] = CubDB.select(context.db) |> Enum.to_list()
    refute FileFs.has_file?({"chunk-key", 0, 2}, context.files_path)
  end

  test "asks for fsync after enough writes and resets on it", context do
    state =
      writer_state(context)
      |> db_write(1..11 |> Enum.map(&{{:item, &1}, &1}))

    assert fsync_needed?(state)
    refute state |> fsync() |> fsync_needed?()
  end

  test "fsync timer starts once and cancels safely", context do
    state = writer_state(context)

    assert state == cancel_fsync_timer(state)

    started = start_fsync_timer(state)
    assert started == start_fsync_timer(started)
    assert state == cancel_fsync_timer(started)
  end

  test "demanding a dead queue keeps the state", context do
    state = writer_state(context)

    assert state == demand_queue(state)
  end

  test "write/2 and delete/2 cast the operation" do
    Writer.write(self(), [:a])
    Writer.delete(self(), [:b])

    assert_receive {:"$gen_cast", {:write, [:a]}}
    assert_receive {:"$gen_cast", {:delete, [:b]}}
  end

  test "writer process stores mirrored payloads", context do
    queue = start_supervised!(WriteQueue)
    compactor = start_supervised!({Compactor, name: nil, db: context.db})

    writer =
      start_supervised!(
        {WriterProcess,
         name: nil,
         db: context.db,
         files_path: context.files_path,
         queue: queue,
         compactor: compactor}
      )

    GenServer.cast(writer, {:mirror, {:write, [{:mirrored, 1}]}})
    :sys.get_state(writer)

    assert 1 == CubDB.get(context.db, :mirrored)
  end

  defp writer_state(context) do
    from_opts(
      db: context.db,
      files_path: context.files_path,
      queue: __MODULE__.NoQueue,
      compactor: nil
    )
  end
end
