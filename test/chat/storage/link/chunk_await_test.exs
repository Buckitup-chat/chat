defmodule Chat.Storage.Link.ChunkAwaitTest do
  use Chat.Test.PgPairCase, mode: :committed, async: false

  import Chat.Storage.Link, only: [~>: 2]

  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Storage.Link
  alias Chat.Storage.Links
  alias Chat.Test.PgPair.Files

  @moduletag :capture_log

  @opts [poll_ms: 20, stall_ms: 200]

  setup do
    on_exit(fn -> :ets.delete_all_objects(Links) end)
  end

  describe "await/3 :chunks" do
    test "returns once `to` holds every chunk sourced from `from`", %{unit_a: a, unit_b: b} do
      file_id = Files.new_file_id()
      Files.missing!(UnitBRepo, file_id, 0, a.system_id)
      Files.missing!(UnitBRepo, file_id, 1, "sys_other")
      link = a ~> b

      awaiting = self()

      spawn_link(fn ->
        send(awaiting, {:awaited, Link.await([link], :chunks, poll_ms: 20, stall_ms: 5_000)})
      end)

      Process.sleep(60)
      assert {:awaiting, {0, 1}} == Links.status(link)

      from(m in MissingChunk, where: m.chunk_index == 0) |> UnitBRepo.delete_all()

      assert_receive {:awaited, :ok}, 2_000
      assert :idle == Links.status(link)
    end

    test "gives up after the stall timeout without progress", %{unit_a: a, unit_b: b} do
      Files.missing!(UnitBRepo, Files.new_file_id(), 0, a.system_id)

      assert {:stalled, %{{:main, :backup} => 1}} == Link.await([a ~> b], :chunks, @opts)
    end

    test "nothing to wait for", %{unit_a: a, unit_b: b} do
      assert :ok == Link.await([a ~> b, b ~> a], :chunks, @opts)
    end
  end
end
