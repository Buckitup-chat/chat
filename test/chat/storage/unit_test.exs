defmodule Chat.Storage.UnitTest do
  use ExUnit.Case, async: false

  alias Chat.Storage.Unit

  @target [internal_root: "/root", media_root: "/root/media"]
  @host [internal_root: "priv", media_root: "priv/media"]

  @target_paths %{
    internal: {:internal, "/root/db"},
    main: {"sdb1", "/root/media/sdb1/main_db"},
    backup: {"sdb1", "/root/media/sdb1/backup_db"},
    cargo: {"sdb1", "/root/media/sdb1/cargo_db"},
    onliners: {"sdb1", "/root/media/sdb1/onliners_db"}
  }
  @host_paths %{
    internal: {:internal, "priv/db"},
    main: {"sdc1", "priv/media/sdc1/main_db"},
    backup: {"sdc1", "priv/media/sdc1/backup_db"},
    cargo: {"sdc1", "priv/media/sdc1/cargo_db"},
    onliners: {"sdc1", "priv/media/sdc1/onliners_db"}
  }
  @segments %{
    cub_db: "v.10.1",
    cub_files: "v.10.1_files",
    pg: "pg",
    pq_files: "pq_files",
    electric: "electric"
  }

  setup do
    original = Application.fetch_env!(:chat, Chat.Storage)
    on_exit(fn -> Application.put_env(:chat, Chat.Storage, original) end)
  end

  describe "path/2 on target" do
    setup do: use_storage_config(@target)

    for {role, {id, dir}} <- @target_paths, {resource, segment} <- @segments do
      test "#{role} #{resource}" do
        unit = unit_for(unquote(role), unquote(id))
        assert unit.id == unquote(id)
        assert Unit.path(unit, unquote(resource)) == Path.join(unquote(dir), unquote(segment))
      end
    end

    test "CubDB paths equal today's" do
      assert Unit.internal() |> Unit.path(:cub_db) == "/root/db/v.10.1"
      assert Unit.internal() |> Unit.path(:cub_files) == "/root/db/v.10.1_files"
      assert Unit.usb("sdb1", :main) |> Unit.path(:cub_db) == "/root/media/sdb1/main_db/v.10.1"

      assert Unit.usb("sdb1", :backup) |> Unit.path(:cub_files) ==
               "/root/media/sdb1/backup_db/v.10.1_files"
    end

    test "pg_run is per device" do
      assert Unit.internal() |> Unit.pg_run() == "/tmp/pg_run/internal"
      assert Unit.usb("sdb1", :main) |> Unit.pg_run() == "/tmp/pg_run/sdb1"
    end
  end

  describe "path/2 on host" do
    setup do: use_storage_config(@host)

    for {role, {id, dir}} <- @host_paths, {resource, segment} <- @segments do
      test "#{role} #{resource}" do
        unit = unit_for(unquote(role), unquote(id))
        assert Unit.path(unit, unquote(resource)) == Path.join(unquote(dir), unquote(segment))
      end
    end

    test "pg_run is per device" do
      assert Unit.internal() |> Unit.pg_run() == "/tmp/pg_run/internal"
      assert Unit.usb("sdc1", :main) |> Unit.pg_run() == "/tmp/pg_run/sdc1"
    end
  end

  describe "engine naming" do
    test "pg_port matches BootSupervisor's device letter derivation" do
      assert Unit.internal() |> Unit.pg_port() == 5432
      assert Unit.usb("sda1", :main) |> Unit.pg_port() == 5433
      assert Unit.usb("sdb1", :backup) |> Unit.pg_port() == 5434
      assert Unit.usb("sdd", :cargo) |> Unit.pg_port() == 5436
    end

    test "repo matches BootSupervisor's repo module name" do
      assert Unit.internal() |> Unit.repo() == Chat.Repo
      assert Unit.usb("sdb1", :main) |> Unit.repo() == Platform.Dev.Sdb.Repo
      assert Unit.usb("sdc", :backup) |> Unit.repo() == Platform.Dev.Sdc.Repo
    end

    test "cub_name is one per role" do
      assert Unit.internal() |> Unit.cub_name() == Chat.Db.InternalDb
      assert Unit.usb("sdb1", :main) |> Unit.cub_name() == Chat.Db.MainDb
      assert Unit.usb("sdb1", :backup) |> Unit.cub_name() == Chat.Db.BackupDb
      assert Unit.usb("sdb1", :cargo) |> Unit.cub_name() == Chat.Db.CargoDb
      assert Unit.usb("sdb1", :onliners) |> Unit.cub_name() == Chat.Db.OnlinersDb
    end

    test "via is keyed by component and unit id" do
      assert Unit.usb("sdb1", :main) |> Unit.via(Mounter) ==
               {:via, Registry, {Platform.Drives.Registry, {Mounter, "sdb1"}}}
    end

    test "role_dir and capabilities come from Role" do
      assert Unit.internal() |> Unit.role_dir() == "db"
      assert Unit.usb("sdb1", :cargo) |> Unit.role_dir() == "cargo_db"
      assert Unit.usb("sdb1", :cargo) |> Unit.capabilities() == [:cub]
      assert Unit.usb("sdb1", :main) |> Unit.capabilities() == [:cub, :pg, :pq_files, :pipeline]
    end
  end

  defp use_storage_config(config), do: Application.put_env(:chat, Chat.Storage, config)

  defp unit_for(:internal, :internal), do: Unit.internal()
  defp unit_for(role, device), do: Unit.usb(device, role)
end
