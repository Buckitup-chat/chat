defmodule Chat.Db.Copying.ProgressTest do
  use ExUnit.Case, async: true

  import Rewire

  defmodule DbMock do
    def data_dir(_) do
      "priv/test_admin_db"
    end

    def has_key?(_, _) do
      true
    end
  end

  defmodule FileFsMock do
    def has_file?(_, _) do
      true
    end
  end

  defmodule EmptyFileFsMock do
    def has_file?(_, _) do
      false
    end
  end

  alias Chat.Db.Copying.Progress

  rewire(Progress, [{CubDB, DbMock}, {Chat.FileFs, FileFsMock}])

  test "empty progress should be complete" do
    assert Progress.new([], :db?) |> Progress.complete?()

    assert [] =
             Progress.new([], :db?)
             |> Progress.get_unwritten_keys()

    assert 100 =
             Progress.new([], :db?)
             |> Progress.eliminate_written()
             |> Progress.done_percent()
  end

  rewire(Progress, [{CubDB, DbMock}, {Chat.FileFs, EmptyFileFsMock}])

  test "should return corrent percentage" do
    assert 10 =
             Progress.new([{:any_data}, {:file_chunk, nil, nil, nil}], :db?)
             |> Progress.eliminate_written()
             |> Progress.done_percent()
  end

  test "should delay correctly" do
    delay =
      {:file_chunk, nil, nil, nil}
      |> List.duplicate(2000)
      |> Progress.new(:db?)
      |> Progress.recheck_delay_in_ms()

    assert delay == 5_000

    delay =
      {:file_chunk, nil, nil, nil}
      |> List.duplicate(20_000)
      |> Progress.new(:db?)
      |> Progress.recheck_delay_in_ms()

    assert delay == 29_000
  end
end
