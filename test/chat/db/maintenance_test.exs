defmodule Chat.Db.MaintenanceTest do
  use ExUnit.Case, async: true
  import Rewire

  defmodule CubDbMock do
    def current_db_file(_), do: "/fake/size_1234"
    def data_dir(:db?), do: "/fake"
  end

  defmodule FileStatMock do
    def stat!("/fake/size_1234"), do: %{size: 1234}
    def exists?(_), do: true
  end

  defmodule SystemMock do
    def cmd("df", _),
      do:
        {"""
         Filesystem     1024-blocks      Used Available Capacity  Mounted on
         /dev/disk1s5s1   244810132   8863632  18496604    33%    /
         """, 0}
  end

  alias Chat.Db.Maintenance

  rewire(Maintenance, CubDB: CubDbMock, File: FileStatMock, System: SystemMock)

  test "writeble space should be 100 mb less" do
    total = Maintenance.path_free_space("/tmp")
    writeble = Maintenance.path_writable_size("/tmp")

    assert writeble + 100 * 1024 * 1024 == total
  end

  test "check size" do
    assert 1234 = Maintenance.db_size(:db?)
  end

  test "path to device" do
    assert "/dev/disk1s5s1" = Maintenance.path_to_device("/fake")
  end

  test "device to path" do
    assert "/fake" = Maintenance.device_to_path("/dev/disk1s5s1")
  end
end
