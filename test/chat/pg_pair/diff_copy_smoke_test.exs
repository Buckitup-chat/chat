defmodule Chat.PgPair.DiffCopySmokeTest do
  use Chat.Test.PgPairCase, mode: :sandbox, async: true

  alias Chat.Storage.Pg.BatchSync
  alias Chat.Test.PgPair.User

  @moduletag :capture_log

  @users from(u in "users", select: %{pub_key: u.pub_key, name: u.name})

  test "row inserted on A is diff-copied to B", %{unit_a: unit_a, unit_b: unit_b} do
    UnitARepo.insert_all("users", [%{pub_key: <<1, 2, 3>>, name: "alice"}])

    assert {:ok, %{User => 1}} =
             BatchSync.sync(source_repo: unit_a.repo, target_repo: unit_b.repo, schemas: [User])

    assert [%{pub_key: <<1, 2, 3>>, name: "alice"}] = UnitBRepo.all(@users)
  end

  test "unit fixtures carry real temp dirs and the cluster system id", %{unit_a: a, unit_b: b} do
    assert File.dir?(Path.join(a.root, "pq_files"))
    assert File.dir?(Path.join(b.root, "cub"))
    assert a.root != b.root
    assert is_integer(a.system_id) and a.system_id == b.system_id
  end
end
