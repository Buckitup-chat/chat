defmodule Chat.Storage.Link.BootstrapBranchesTest do
  # registers the global CubDB names of main and backup, and shares the `Links` table
  use ExUnit.Case, async: false

  import Support.Rewire

  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.UserCard
  alias Chat.Storage.Link
  alias Chat.Storage.Link.Bootstrap
  alias Chat.Storage.Link.Filter
  alias Chat.Storage.Links
  alias Chat.Storage.Unit

  @moduletag :capture_log

  @main Unit.usb("sdb1", :main)
  @backup Unit.usb("sdc1", :backup)
  @cards_only %Filter{schemas: [UserCard]}
  @disk_full %Postgrex.Error{postgres: %{code: :disk_full}}

  defmodule CopyingSpy do
    def await_copied(from, to, keys) do
      send(self(), {:await_copied, from, to, keys})
      :ok
    end
  end

  defmodule BatchSyncOk do
    def sync(_opts), do: {:ok, %{}}
  end

  defmodule BatchSyncPartial do
    def sync(_opts), do: {:partial, %{}, %{UserCard => :timeout}}
  end

  defmodule BatchSyncPartialDiskFull do
    def sync(_opts),
      do: {:partial, %{}, %{UserCard => %Postgrex.Error{postgres: %{code: :disk_full}}}}
  end

  defmodule BatchSyncFails do
    def sync(_opts), do: {:error, :boom}
  end

  defmodule BatchSyncDiskFull do
    def sync(_opts), do: {:error, {:aborted, %Postgrex.Error{postgres: %{code: :disk_full}}}}
  end

  defmodule RepoDown do
    def all(_query), do: raise(%Postgrex.Error{message: "connection closed"})
  end

  defmodule UnitRepoDown do
    def repo(_unit), do: RepoDown
    defdelegate cub_name(unit), to: Chat.Storage.Unit
  end

  setup do
    on_exit(fn -> :ets.delete_all_objects(Links) end)
  end

  describe "run/1 CubDB layer" do
    test "awaits the CubDB copy of the filter's keys before the rows" do
      Enum.each([@main, @backup], &fake_cub/1)
      keys = MapSet.new([:key])
      filter = %{@cards_only | cub_scope: fn _link -> keys end}
      link = Link.new(@main, @backup, filter: filter)
      bootstrap = rewire(Bootstrap, Copying: CopyingSpy, BatchSync: BatchSyncOk)

      assert [:cub, :pg] == Link.layers(link)
      assert :ok = bootstrap.run(link)
      assert_received {:await_copied, Chat.Db.MainDb, Chat.Db.BackupDb, ^keys}
      assert :idle == Links.status(link)
    end
  end

  # a process under the unit's CubDB name, so the unit counts as running
  defp fake_cub(unit) do
    name = Unit.cub_name(unit)
    assert nil == Process.whereis(name)

    pid = spawn(fn -> Process.sleep(:infinity) end)
    Process.register(pid, name)
    on_exit(fn -> Process.exit(pid, :kill) end)
  end

  describe "run/1 rows layer" do
    test "reports the schemas that failed to copy" do
      link = Link.new(@main, @backup, filter: @cards_only)
      bootstrap = rewire(Bootstrap, BatchSync: BatchSyncPartial)

      assert {:partial, %{UserCard => :timeout}} = bootstrap.run(link)
      assert {:partial, %{UserCard => :timeout}} == Links.status(link)
    end

    test "turns a partial copy that ran out of disk into disk full" do
      link = Link.new(@main, @backup, filter: @cards_only)
      bootstrap = rewire(Bootstrap, BatchSync: BatchSyncPartialDiskFull)

      assert {:error, :disk_full} = bootstrap.run(link)
      assert {:error, :disk_full} == Links.status(link)
    end

    test "stops at a failed copy" do
      link = Link.new(@main, @backup)
      bootstrap = rewire(Bootstrap, BatchSync: BatchSyncFails, Unit: UnitRepoDown)

      assert [:pg, :blobs] == Link.layers(link)
      assert {:error, :boom} = bootstrap.run(link)
      assert {:error, :boom} == Links.status(link)
    end

    test "turns a failed copy that ran out of disk into disk full" do
      link = Link.new(@main, @backup, filter: @cards_only)
      bootstrap = rewire(Bootstrap, BatchSync: BatchSyncDiskFull)

      assert {:error, :disk_full} = bootstrap.run(link)
    end
  end

  describe "run/1 chunks layer" do
    test "reports a PostgreSQL failure while backfilling missing chunks" do
      link = Link.new(@main, @backup)
      bootstrap = rewire(Bootstrap, BatchSync: BatchSyncOk, Unit: UnitRepoDown)

      assert {:error, %Postgrex.Error{message: "connection closed"}} = bootstrap.run(link)
    end
  end

  describe "disk_full?/1" do
    test "finds a full disk in file errors and lists" do
      assert Bootstrap.disk_full?(%File.Error{reason: :enospc})
      assert Bootstrap.disk_full?([:ok, @disk_full])
      refute Bootstrap.disk_full?([:ok, %File.Error{reason: :eacces}])
      refute Bootstrap.disk_full?(%{FileChunk => :timeout})
    end
  end
end
