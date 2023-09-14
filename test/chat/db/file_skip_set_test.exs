defmodule Chat.Db.WriteQueue.FileSkipSetTest do
  use ExUnit.Case, async: true

  alias Chat.Db.WriteQueue.FileSkipSet

  setup do
    ref = FileSkipSet.new()

    on_exit(fn ->
      FileSkipSet.delete(ref)
    end)

    {:ok, ref: ref}
  end

  test "add_skipped_file/2 adds a file tuple to the set", %{ref: ref} do
    assert FileSkipSet.add_skipped_file(ref, {:file, 1})
    assert FileSkipSet.member?(ref, {:file, 1})
  end

  test "member?/2 returns true if file tuple is in the set", %{ref: ref} do
    assert FileSkipSet.add_skipped_file(ref, {:file, 1})
    assert FileSkipSet.member?(ref, {:file, 1})
  end

  test "member?/2 returns false if file tuple is not in the set", %{ref: ref} do
    refute FileSkipSet.member?(ref, {:file, 1})
  end

  test "add_skipped_file/2 returns false if ref is nil" do
    refute FileSkipSet.add_skipped_file(nil, {:file, 1})
  end

  test "member?/2 returns false if ref is nil" do
    refute FileSkipSet.member?(nil, {:file, 1})
  end
end

#
# defmodule FileSkipSetTest do
#  use ExUnit.Case
#
#  alias FileSkipSet
#
#  @moduletag :capture_log
#
#  doctest FileSkipSet
#
#  test "module exists" do
#    assert is_list(FileSkipSet.module_info())
#  end
# end
