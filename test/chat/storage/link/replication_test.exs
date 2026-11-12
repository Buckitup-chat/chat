defmodule Chat.Storage.Link.ReplicationTest do
  use Chat.Test.PgPairCase, mode: :committed, async: false

  import Chat.Storage.Link, only: [~>: 2]

  alias Chat.Data.File.ChunkStore
  alias Chat.Data.File.DriveCopySource
  alias Chat.Data.File.ReplicationListener
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Data.Schemas.UserCard
  alias Chat.Storage.Link
  alias Chat.Storage.Links
  alias Chat.Storage.Pg.LogicalReplicator
  alias Chat.Storage.Unit
  alias Chat.Storage.Units
  alias Chat.Test.PgPair.Files
  alias Chat.Test.PgPairHelper.Db

  @moduletag :capture_log

  setup do
    on_exit(fn -> :ets.delete_all_objects(Links) end)
  end

  describe "replicate/1" do
    test "streams rows and registers `from` as the source of `to`", %{unit_a: a, unit_b: b} do
      link = a ~> b

      assert :ok = Link.replicate(link)
      Files.user_card!(UnitARepo)

      assert [_card] = await_replicated(UnitBRepo, UserCard)
      assert :replicating == Links.status(link)
      assert "sys_unit_a" == Links.replication_source(b)
      assert {:ok, lag} = Link.lag(link)
      assert lag >= 0
    end
  end

  describe "stop/1" do
    test "drops the subscription on `to` and the slot on `from`", %{unit_a: a, unit_b: b} do
      link = a ~> b
      :ok = Link.replicate(link)

      assert :ok = Link.stop(link)

      assert [] == Db.rows(UnitBRepo, "SELECT subname FROM pg_subscription")
      refute slot?("backup_from_main")
      assert :stopped == Links.status(link)
      assert nil == Links.replication_source(b)
    end

    test "drops the slot on `from` even when `to` is gone", %{unit_a: a, unit_b: b} do
      :ok = Link.replicate(a ~> b)
      # `to` vanished: its subscription is gone, the slot on `from` is left behind
      :ok =
        LogicalReplicator.drop_subscription_if_exists(
          UnitBRepo,
          "backup_from_main"
        )

      assert slot?("backup_from_main")

      gone = %Unit{id: "sdq1", role: :backup, root: b.root, system_id: b.system_id}

      assert :ok = Link.stop(a ~> gone)
      refute slot?("backup_from_main")
    end
  end

  # main (a) ~> backup (b), with the app's own internal unit up as the third one
  describe "three units up" do
    setup %{unit_a: a, unit_b: b} do
      {:ok, internal} = Units.by_role(:internal)
      file_id = Files.new_file_id()
      on_exit(fn -> ChunkStore.delete_file(internal, file_id) end)

      Enum.each([a, b], &register!/1)
      start_supervised!({ReplicationListener, unit: b})

      %{internal: internal, file_id: file_id}
    end

    test "replicated chunks are fetched from the unit they came from",
         %{unit_a: a, unit_b: b, internal: internal, file_id: file_id} do
      :ok = ChunkStore.put(a, file_id, 0, "from a")
      :ok = ChunkStore.put(internal, file_id, 0, "from internal")

      :ok = Link.replicate(a ~> b)
      Files.file!(UnitARepo, file_id, 1)

      [%{source_drive_id: source}] =
        await_replicated(UnitBRepo, from(m in MissingChunk, where: not is_nil(m.data_hash)))

      assert "sys_unit_a" == source
      assert {:ok, "from a"} == DriveCopySource.fetch_chunk(%{unit: b}, file_id, 0, source)
    end
  end

  # entries belong to the test process and go away with it
  defp register!(unit), do: :ok = Units.register(unit)

  defp slot?(name) do
    UnitARepo
    |> Db.rows("SELECT 1 FROM pg_replication_slots WHERE slot_name = $1", [name])
    |> Enum.any?()
  end
end
