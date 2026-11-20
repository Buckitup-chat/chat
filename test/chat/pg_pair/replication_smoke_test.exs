defmodule Chat.PgPair.ReplicationSmokeTest do
  use Chat.Test.PgPairCase, mode: :committed, async: false

  alias Chat.Test.PgPairHelper.Db

  test "row committed on A replicates to B through a separately created slot" do
    :ok = subscribe(UnitARepo, UnitBRepo, "pg_pair_smoke", ["users"])

    UnitARepo.insert_all("users", [%{pub_key: <<9, 9, 9>>, name: "replicated"}])

    query = from(u in "users", where: u.pub_key == ^<<9, 9, 9>>, select: u.name)
    assert ["replicated"] = await_replicated(UnitBRepo, query)
  end

  # holds in either order: before the replication test (fresh pair) or after it (on_exit reset)
  test "no subscription, slot or rows leak between committed tests" do
    names = from(u in "users", select: u.name)

    assert [] = UnitARepo.all(names)
    assert [] = UnitBRepo.all(names)
    assert [] = Db.rows(UnitBRepo, "SELECT subname FROM pg_subscription")

    assert [] =
             Db.rows(
               UnitARepo,
               "SELECT slot_name FROM pg_replication_slots WHERE database = ANY($1)",
               [databases()]
             )
  end
end
