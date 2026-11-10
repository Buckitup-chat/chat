defmodule Chat.PgPair.DiffCopySmokeTest do
  use Chat.Test.PgPairCase, mode: :sandbox, async: true

  @users from(u in "users", select: %{pub_key: u.pub_key, name: u.name})

  test "row inserted on A is diff-copied to B", %{unit_a: unit_a, unit_b: unit_b} do
    UnitARepo.insert_all("users", [%{pub_key: <<1, 2, 3>>, name: "alice"}])

    # stand-in for Chat.Storage.Pg.BatchSync until it moves to chat (#797)
    copy_missing(unit_a.repo, unit_b.repo)

    assert [%{pub_key: <<1, 2, 3>>, name: "alice"}] = UnitBRepo.all(@users)
  end

  test "unit fixtures carry real temp dirs and the cluster system id", %{unit_a: a, unit_b: b} do
    assert File.dir?(Path.join(a.root, "pq_files"))
    assert File.dir?(Path.join(b.root, "cub"))
    assert a.root != b.root
    assert is_integer(a.system_id) and a.system_id == b.system_id
  end

  defp copy_missing(from, to) do
    present = from(u in "users", select: u.pub_key) |> to.all() |> MapSet.new()

    from.all(@users)
    |> Enum.reject(&MapSet.member?(present, &1.pub_key))
    |> then(&to.insert_all("users", &1, on_conflict: :nothing))
  end
end
