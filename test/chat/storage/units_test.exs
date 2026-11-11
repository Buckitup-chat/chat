defmodule Chat.Storage.UnitsTest do
  use ExUnit.Case, async: false

  alias Chat.Storage.Unit
  alias Chat.Storage.Units

  @main %{Unit.usb("sdz1", :main) | system_id: "main-sid"}
  @backup %{Unit.usb("sdy1", :backup) | system_id: "backup-sid"}
  @cargo Unit.usb("sdx1", :cargo)

  describe "register/1" do
    test "rejects a second unit with the same role" do
      owner = register_from_process(@main)

      assert {:error, {:already_registered, ^owner}} =
               Units.register(%{Unit.usb("sdw1", :main) | system_id: "other-sid"})

      assert {:ok, @main} = Units.by_role(:main)
    end

    test "requires a system id for a unit with PG" do
      assert {:error, :no_system_id} = Units.register(Unit.usb("sdz1", :main))
      assert :error = Units.by_role(:main)
    end

    test "accepts a unit without PG and without a system id" do
      register_from_process(@cargo)

      assert {:ok, @cargo} = Units.by_role(:cargo)
    end
  end

  describe "by_system_id/1" do
    test "resolves while the owner is up and returns :error after it stops" do
      owner = register_from_process(@backup)

      assert {:ok, @backup} = Units.by_system_id("backup-sid")

      stop(owner)

      assert :error = Units.by_system_id("backup-sid")
    end
  end

  describe "lookups" do
    setup do
      register_from_process(@main)
      register_from_process(@backup)
      :ok
    end

    test "by_id/1 and by_role/1" do
      assert {:ok, @backup} = Units.by_id("sdy1")
      assert {:ok, @main} = Units.by_role(:main)
      assert :error = Units.by_id("sdq1")
      assert :error = Units.by_role(:onliners)
    end

    test "list/0 and others/1" do
      assert @main in Units.list()
      assert @backup in Units.list()
      refute @main in Units.others(@main)
      assert @backup in Units.others(@main)
    end
  end

  test "unregister/1 drops the caller's entry" do
    :ok = Units.register(@main)
    assert {:ok, @main} = Units.by_role(:main)

    :ok = Units.unregister(@main)

    assert :error = Units.by_role(:main)
  end

  # Registry entries belong to the registering process, so each unit gets its own owner
  defp register_from_process(unit) do
    test_pid = self()

    owner =
      spawn(fn ->
        send(test_pid, {:registered, Units.register(unit)})
        Process.sleep(:infinity)
      end)

    assert_receive {:registered, :ok}
    on_exit(fn -> stop(owner) end)
    owner
  end

  defp stop(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, _, _, _}
    await_dropped(pid, 50)
  end

  # Registry drops a dead owner's entries asynchronously
  defp await_dropped(pid, tries) do
    owners = Chat.Storage.Units.Registry |> Registry.select([{{:_, :"$1", :_}, [], [:"$1"]}])

    cond do
      pid not in owners ->
        :ok

      tries == 0 ->
        flunk("registry kept the entry of #{inspect(pid)}")

      true ->
        Process.sleep(10)
        await_dropped(pid, tries - 1)
    end
  end
end
