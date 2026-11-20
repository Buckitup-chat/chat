defmodule Chat.Storage.UnitAnnouncerTest do
  use ChatWeb.DataCase, async: false, shared_sandbox: true

  alias Chat.Storage.Pg
  alias Chat.Storage.Unit
  alias Chat.Storage.UnitAnnouncer
  alias Chat.Storage.Units

  # No `sdz` repo exists in chat tests, so the unit carries Chat.Repo's system id.
  # It is also the internal unit's, so lookups here go by id or role, not by system id.
  setup do
    Phoenix.PubSub.subscribe(Chat.PubSub, "storage")
    %{unit: %{Unit.usb("sdz1", :main) | system_id: Pg.system_identifier(Chat.Repo)}}
  end

  describe "start" do
    test "registers the unit and broadcasts :unit_up", %{unit: unit} do
      pid = start_announcer(unit)

      assert_receive {:unit_up, ^unit}
      assert {:ok, ^unit} = Units.by_id("sdz1")
      assert {:ok, ^unit} = Units.by_role(:main)

      GenServer.stop(pid)
    end

    test "reads the system id from the unit's repo when the unit has none" do
      unit = Unit.internal() |> Map.put(:role, :backup)

      pid = start_announcer(unit)

      assert_receive {:unit_up, %Unit{role: :backup, system_id: system_id}}
      assert system_id == Pg.system_identifier(Chat.Repo)

      GenServer.stop(pid)
    end

    test "is ignored when its role is taken", %{unit: unit} do
      pid = start_announcer(unit)
      assert_receive {:unit_up, _}

      assert :ignore = UnitAnnouncer.start_link(unit: %{unit | id: "sdy1"})
      refute_receive {:unit_up, _}
      assert {:ok, %Unit{id: "sdz1"}} = Units.by_role(:main)

      GenServer.stop(pid)
    end

    test "is ignored without a system id" do
      assert :ignore = UnitAnnouncer.start_link(unit: Unit.usb("sdx1", :main))
      refute_receive {:unit_up, _}
    end
  end

  describe "stop" do
    test "unregisters the unit and broadcasts :unit_down", %{unit: unit} do
      pid = start_announcer(unit)
      assert_receive {:unit_up, _}

      GenServer.stop(pid)

      assert_receive {:unit_down, ^unit}
      assert :error = Units.by_id("sdz1")
      assert :error = Units.by_role(:main)
    end
  end

  defp start_announcer(unit) do
    {:ok, pid} = UnitAnnouncer.start_link(unit: unit)
    pid
  end
end
