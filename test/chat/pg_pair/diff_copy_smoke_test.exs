defmodule Chat.PgPair.DiffCopySmokeTest do
  use Chat.Test.PgPairCase, mode: :sandbox, async: true

  alias Chat.Storage.Pg.BatchSync
  alias Chat.Storage.Unit
  alias Chat.Test.PgPair.User

  @moduletag :capture_log

  @users from(u in "users", select: %{pub_key: u.pub_key, name: u.name})

  test "row inserted on A is diff-copied to B", %{unit_a: unit_a, unit_b: unit_b} do
    UnitARepo.insert_all("users", [%{pub_key: <<1, 2, 3>>, name: "alice"}])

    assert {:ok, %{User => 1}} =
             BatchSync.sync(
               source_repo: Unit.repo(unit_a),
               target_repo: Unit.repo(unit_b),
               schemas: [User]
             )

    assert [%{pub_key: <<1, 2, 3>>, name: "alice"}] = UnitBRepo.all(@users)
  end

  test "unit fixtures are units on the pair's repos with real pq_files dirs",
       %{unit_a: a, unit_b: b} do
    assert {UnitARepo, UnitBRepo} == {Unit.repo(a), Unit.repo(b)}
    assert File.dir?(Unit.path(a, :pq_files))
    assert File.dir?(Unit.path(b, :pq_files))
    assert a.root != b.root
    assert a.system_id != b.system_id
    assert system_id(UnitARepo) == system_id(UnitBRepo)
  end
end
