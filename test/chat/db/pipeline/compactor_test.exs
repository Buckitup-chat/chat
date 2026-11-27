defmodule Chat.Db.Pipeline.CompactorTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.Db.Pipeline.Compactor

  defmodule NoSpaceMock do
    def db_free_space(_db), do: 0
    def db_size(_db), do: 1
  end

  rewire(Compactor, [{Chat.Db.Maintenance, NoSpaceMock}, as: FullDiskCompactor])

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    %{db: start_supervised!({CubDB, data_dir: dir})}
  end

  test "starts compaction after inactivity and halts it on activity", %{db: db} do
    compactor = start_supervised!({Compactor, name: nil, db: db})

    send(compactor, :start)
    assert {true, ^db, _} = :sys.get_state(compactor)

    Compactor.activity(compactor)
    assert {false, ^db, timer} = :sys.get_state(compactor)
    assert is_integer(Process.read_timer(timer))
  end

  test "skips compaction when disk has no room for it", %{db: db} do
    compactor = start_supervised!({FullDiskCompactor, name: nil, db: db})

    send(compactor, :start)

    assert {false, ^db, _} = :sys.get_state(compactor)
    refute CubDB.compacting?(db)
  end
end
