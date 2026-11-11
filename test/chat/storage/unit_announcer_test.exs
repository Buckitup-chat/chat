defmodule Chat.Storage.UnitAnnouncerTest do
  use ChatWeb.DataCase, async: false, shared_sandbox: true

  alias Chat.Storage.Unit
  alias Chat.Storage.UnitAnnouncer
  alias Chat.Storage.Units

  setup do
    Phoenix.PubSub.subscribe(Chat.PubSub, "storage")
    Phoenix.PubSub.subscribe(Chat.PubSub, "chunk_pipeline")
    %{unit: Unit.usb("sdz1", :main)}
  end

  describe "start" do
    test "registers the unit with its system id and broadcasts :unit_up", %{unit: unit} do
      pid = start_announcer(unit)

      assert_receive {:unit_up, %Unit{id: "sdz1", system_id: system_id} = up}
      assert is_binary(system_id) and system_id != ""
      assert {:ok, ^up} = Units.by_id("sdz1")
      assert {:ok, ^up} = Units.by_role(:main)

      GenServer.stop(pid)
    end

    test "keeps broadcasting the legacy :drive_mounted", %{unit: unit} do
      pid = start_announcer(unit)

      assert_receive {:unit_up, %Unit{system_id: system_id}}
      assert_receive {:chunk_pipeline, {:drive_mounted, ^system_id}}

      GenServer.stop(pid)
    end

    test "is ignored when its role is taken", %{unit: unit} do
      pid = start_announcer(unit)
      assert_receive {:unit_up, _}

      assert :ignore = UnitAnnouncer.start_link(unit: Unit.usb("sdy1", :main), repo: Chat.Repo)
      refute_receive {:unit_up, _}
      assert {:ok, %Unit{id: "sdz1"}} = Units.by_role(:main)

      GenServer.stop(pid)
    end

    test "is ignored without a repo" do
      assert :ignore = UnitAnnouncer.start_link(repo: nil)
    end

    test "without a unit broadcasts the legacy event only" do
      {:ok, pid} = UnitAnnouncer.start_link(repo: Chat.Repo)

      assert_receive {:chunk_pipeline, {:drive_mounted, _system_id}}
      refute_receive {:unit_up, _}

      GenServer.stop(pid)
    end
  end

  describe "stop" do
    test "unregisters the unit and broadcasts :unit_down", %{unit: unit} do
      pid = start_announcer(unit)
      assert_receive {:unit_up, %Unit{system_id: system_id}}

      GenServer.stop(pid)

      assert_receive {:unit_down, %Unit{id: "sdz1", system_id: ^system_id}}
      assert_receive {:chunk_pipeline, {:drive_unmounted, ^system_id}}
      assert :error = Units.by_id("sdz1")
      assert :error = Units.by_role(:main)
    end
  end

  # Chat.Repo stands in for the drive's repo. It is also the internal unit's repo, so
  # both share one system id: lookups here go by id or role, not by system id.
  defp start_announcer(unit) do
    {:ok, pid} = UnitAnnouncer.start_link(unit: unit, repo: Chat.Repo)
    pid
  end
end
