defmodule Chat.Storage.RoleTest do
  use ExUnit.Case, async: true

  alias Chat.Storage.Role

  describe "capabilities/1 and dir/1" do
    test "PG roles and CubDB-only roles" do
      for role <- [:internal, :main, :backup] do
        assert Role.capabilities(role) == [:cub, :pg, :pq_files, :pipeline]
      end

      assert Role.capabilities(:cargo) == [:cub]
      assert Role.capabilities(:onliners) == [:cub]
    end

    test "dirs" do
      assert Enum.map(Role.all(), &{&1, Role.dir(&1)}) |> Enum.sort() == [
               backup: "backup_db",
               cargo: "cargo_db",
               internal: "db",
               main: "main_db",
               onliners: "onliners_db"
             ]
    end
  end

  describe "from_mount/1" do
    @describetag :tmp_dir

    test "empty drive is blank", %{tmp_dir: mount} do
      assert Role.from_mount(mount) == :blank
    end

    test "drive without role dirs is blank", %{tmp_dir: mount} do
      mkdirs(mount, ["DCIM", "pg"])
      assert Role.from_mount(mount) == :blank
    end

    test "single role", %{tmp_dir: mount} do
      for {dir, role} <- [main_db: :main, backup_db: :backup, cargo_db: :cargo] do
        File.rm_rf!(mount)
        mkdirs(mount, ["#{dir}/v.10.1"])
        assert Role.from_mount(mount) == {:ok, role}
      end
    end

    test "legacy multi-role drive resolves by priority", %{tmp_dir: mount} do
      mkdirs(mount, ["main_db/v.10.1", "backup_db/v.10.1"])
      assert Role.from_mount(mount) == {:ok, :backup}

      mkdirs(mount, ["onliners_db/v.10.1"])
      assert Role.from_mount(mount) == {:ok, :onliners}

      mkdirs(mount, ["cargo_db/v.10.1"])
      assert Role.from_mount(mount) == {:ok, :cargo}
    end

    test "multi-role drive with a single pg/ still resolves by priority", %{tmp_dir: mount} do
      mkdirs(mount, ["main_db/pg", "backup_db/v.10.1"])
      assert Role.from_mount(mount) == {:ok, :backup}
    end

    test "multi-role drive with several pg/ clusters is an error", %{tmp_dir: mount} do
      mkdirs(mount, ["main_db/pg", "backup_db/pg", "cargo_db/v.10.1"])
      assert Role.from_mount(mount) == {:error, {:multiple_roles, [:backup, :main]}}
    end
  end

  defp mkdirs(mount, dirs), do: Enum.each(dirs, &File.mkdir_p!(Path.join(mount, &1)))
end
