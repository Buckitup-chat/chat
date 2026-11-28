defmodule Chat.Storage.Link.ReplicationBranchesTest do
  # registers the global CubDB names of main and backup, and shares the `Links` table
  use ExUnit.Case, async: false

  import Chat.Storage.Link, only: [~>: 2]
  import Support.Rewire

  alias Chat.Storage.Link
  alias Chat.Storage.Links
  alias Chat.Storage.Unit

  @moduletag :capture_log

  @main Unit.usb("sdb1", :main)
  @backup Unit.usb("sdc1", :backup)

  defmodule ReplicatorOk do
    def follow(_source, _target, _tables, _publication, _slot), do: :ok
    def drop_subscription_if_exists(_repo, _name), do: :ok
    def release_slot(_repo, _name), do: :ok
    def check_replication_lag(_repo, _name), do: {:ok, 0}
  end

  defmodule ReplicatorFails do
    def follow(_source, _target, _tables, _publication, _slot), do: {:error, :boom}
    defdelegate drop_subscription_if_exists(repo, name), to: ReplicatorOk
    defdelegate release_slot(repo, name), to: ReplicatorOk
    defdelegate check_replication_lag(repo, name), to: ReplicatorOk
  end

  defmodule ReplicatorExits do
    def check_replication_lag(_repo, _name), do: exit(:noproc)
    defdelegate follow(source, target, tables, publication, slot), to: ReplicatorOk
    defdelegate drop_subscription_if_exists(repo, name), to: ReplicatorOk
    defdelegate release_slot(repo, name), to: ReplicatorOk
  end

  defmodule SwitchingSpy do
    def mirror(from, to), do: send(self(), {:mirror, from, to})
    def unmirror(from), do: send(self(), {:unmirror, from})
  end

  setup do
    on_exit(fn -> :ets.delete_all_objects(Links) end)
  end

  describe "start/1" do
    test "records the error when following fails" do
      replication = rewire(Chat.Storage.Link.Replication, LogicalReplicator: ReplicatorFails)
      link = @main ~> @backup

      assert {:error, :boom} = replication.start(link)
      assert {:error, :boom} == Links.status(link)
      assert nil == Links.replication_source(@backup)
    end

    test "mirrors `from`'s CubDB into the running CubDBs it replicates to" do
      Enum.each([@main, @backup], &fake_cub/1)

      replication =
        rewire(Chat.Storage.Link.Replication,
          LogicalReplicator: ReplicatorOk,
          Switching: SwitchingSpy
        )

      link = @main ~> @backup

      assert [:cub, :pg, :blobs] == Link.layers(link)
      assert :ok = replication.start(link)
      assert_received {:mirror, Chat.Db.MainDb, [Chat.Db.BackupDb]}

      assert :ok = replication.stop(link)
      assert_received {:unmirror, Chat.Db.MainDb}
    end

    test "leaves CubDB mirrors alone when `from`'s CubDB is down" do
      replication =
        rewire(Chat.Storage.Link.Replication,
          LogicalReplicator: ReplicatorOk,
          Switching: SwitchingSpy
        )

      assert :ok = replication.start(@main ~> @backup)
      refute_received {:mirror, _from, _to}
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

  describe "lag/1" do
    test "reports a gone `to` as an error" do
      replication = rewire(Chat.Storage.Link.Replication, LogicalReplicator: ReplicatorExits)

      assert {:error, {:exit, :noproc}} = replication.lag(@main ~> @backup)
    end
  end
end
