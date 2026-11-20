defmodule Chat.Storage.LinkTest do
  use ExUnit.Case, async: false

  import Chat.Storage.Link, only: [~>: 2]

  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Shapes
  alias Chat.Storage.Link
  alias Chat.Storage.Link.Filter
  alias Chat.Storage.Links
  alias Chat.Storage.Unit

  @internal Unit.internal()
  @main Unit.usb("sdb1", :main)
  @cargo Unit.usb("sdc1", :cargo)

  setup do
    on_exit(fn -> :ets.delete_all_objects(Links) end)
  end

  describe "identity" do
    test "~> builds an unfiltered link" do
      assert %Link{from: @internal, to: @main, filter: :all} == @internal ~> @main
      assert Link.new(@internal, @main) == @internal ~> @main
    end

    test "id/1 is the role pair" do
      assert {:internal, :main} == Link.id(@internal ~> @main)
    end

    test "name/2 gives the publication on `from` and the subscription/slot on `to`" do
      link = @internal ~> @main

      assert "internal_to_main" == Link.name(link, :publication)
      assert "main_from_internal" == Link.name(link, :subscription)
      assert "main_from_internal" == Link.name(link, :slot)
    end
  end

  describe "layers/1" do
    test "a CubDB-only role moves only CubDB, and only while both CubDBs run" do
      assert [] == Link.layers(@internal ~> @cargo)
    end

    test "PG units move rows and blobs" do
      assert [:pg, :blobs] == Link.layers(@main ~> Unit.usb("sdd1", :backup))
    end
  end

  describe "Filter" do
    test ":all syncs every sync schema, chunks included" do
      assert Shapes.sync_schemas() == Filter.schemas(:all)
      assert Filter.chunks?(:all)
      assert nil == Filter.cub_keys(:all, @internal ~> @main)
    end

    test "schemas narrow tables and chunk tracking; cub_scope picks keys" do
      filter = %Filter{schemas: [UserCard], cub_scope: fn %Link{} -> [:key] end}

      assert ["user_cards"] == Filter.tables(filter)
      refute Filter.chunks?(filter)
      assert Filter.chunks?(%Filter{schemas: [UserCard, FileChunk]})
      assert [:key] == Filter.cub_keys(filter, Link.new(@internal, @main, filter: filter))
    end
  end

  describe "Links" do
    test "status, lag and listing" do
      link = @internal ~> @main

      :ok = Links.put_status(link, :replicating)
      :ok = Links.put_lag(link, 42)

      assert :replicating == Links.status(link)
      assert [%{id: {:internal, :main}, status: :replicating, lag_bytes: 42}] == Links.list()
      assert [{:internal, :main}] == Links.replicating_from(:internal)

      :ok = Links.put_status(link, :stopped)
      assert %{status: :stopped, lag_bytes: nil} = Links.list() |> hd()
      assert [] == Links.replicating_from(:internal)
    end

    test "replication source is kept per receiving unit" do
      main = %{@main | system_id: "sys_main"}
      internal = %{@internal | system_id: "sys_internal"}
      backup = %{Unit.usb("sdd1", :backup) | system_id: "sys_backup"}

      :ok = Links.register_source(internal, main)
      assert "sys_main" == Links.replication_source(internal)

      # another link replaced it: unregistering the old one keeps the new one
      :ok = Links.register_source(internal, backup)
      :ok = Links.unregister_source(internal, main)
      assert "sys_backup" == Links.replication_source(internal)

      :ok = Links.unregister_source(internal, backup)
      assert nil == Links.replication_source(internal)
    end
  end
end
