defmodule Chat.Storage.Link.BootstrapTest do
  use Chat.Test.PgPairCase, mode: :committed, async: false

  import Chat.Storage.Link, only: [~>: 2]

  alias Chat.Data.File.ChunkStore
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.UserCard
  alias Chat.Storage.Link
  alias Chat.Storage.Link.Bootstrap
  alias Chat.Storage.Link.Filter
  alias Chat.Storage.Links
  alias Chat.Test.PgPair.Files

  @moduletag :capture_log

  describe "bootstrap/1" do
    test "copies rows and marks chunks without a blob on `to` as missing from `from`",
         %{unit_a: a, unit_b: b} do
      link = a ~> b
      assert [:pg, :blobs] == Link.layers(link)

      file_id = Files.file!(UnitARepo, Files.new_file_id(), 3)
      :ok = ChunkStore.put(b, file_id, 1, "already on b")

      assert :ok = Link.bootstrap(link)

      assert 3 == UnitBRepo.aggregate(FileChunk, :count)
      assert %{0 => "sys_unit_a", 2 => "sys_unit_a"} == Files.missing_sources(UnitBRepo, file_id)
      assert :idle == Links.status(link)
    end

    test "re-sources chunks already missing on `to`", %{unit_a: a, unit_b: b} do
      file_id = Files.file!(UnitARepo, Files.new_file_id(), 1)
      Files.missing!(UnitBRepo, file_id, 0, nil)

      assert :ok = Link.bootstrap(a ~> b)
      assert %{0 => "sys_unit_a"} == Files.missing_sources(UnitBRepo, file_id)
    end

    test "nudges the chunk pipelines only when it queued blobs", %{unit_a: a, unit_b: b} do
      Phoenix.PubSub.subscribe(Chat.PubSub, "chunk_pipeline")

      assert :ok = Link.bootstrap(a ~> b)
      refute_received {:chunk_pipeline, :pg_diff_copied}

      Files.file!(UnitARepo, Files.new_file_id(), 1)
      assert :ok = Link.bootstrap(a ~> b)
      assert_received {:chunk_pipeline, :pg_diff_copied}
    end

    test "a filter without chunk rows tracks no blobs", %{unit_a: a, unit_b: b} do
      file_id = Files.file!(UnitARepo, Files.new_file_id(), 1)
      link = Link.new(a, b, filter: %Filter{schemas: [UserCard]})

      assert [:pg] == Link.layers(link)
      assert :ok = Link.bootstrap(link)
      assert 1 == UnitBRepo.aggregate(UserCard, :count)
      assert %{} == Files.missing_sources(UnitBRepo, file_id)
    end
  end

  describe "disk_full?/1" do
    test "finds PostgreSQL's and the filesystem's disk full at any depth" do
      pg_full = %Postgrex.Error{postgres: %{code: :disk_full}}

      assert Bootstrap.disk_full?(pg_full)
      assert Bootstrap.disk_full?(%{FileChunk => pg_full})
      assert Bootstrap.disk_full?({:aborted, %{reason: :enospc}})

      refute Bootstrap.disk_full?(%{
               FileChunk => %Postgrex.Error{postgres: %{code: :unique_violation}}
             })

      refute Bootstrap.disk_full?({:aborted, %{reason: :closed}})
    end
  end
end
