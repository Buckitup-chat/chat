defmodule Chat.Sync.CargoRoomLifecycleTest do
  use ExUnit.Case, async: false

  alias Chat.Sync.CargoRoom
  alias Phoenix.PubSub

  @cargo_topic "chat::cargo_room"
  @room_key "cargo room key"

  setup do
    PubSub.subscribe(Chat.PubSub, @cargo_topic)
    {:ok, pid} = GenServer.start_link(CargoRoom, :ok)

    %{pid: pid}
  end

  describe "get_room_key/0 on the named server" do
    test "returns the key of the active room" do
      CargoRoom.remove()
      CargoRoom.activate(@room_key)

      assert @room_key = CargoRoom.get_room_key()

      CargoRoom.remove()

      refute CargoRoom.get_room_key()
    end
  end

  describe "activate" do
    test "re-activation cancels the previous countdown timer", %{pid: pid} do
      GenServer.cast(pid, {:activate, @room_key})
      %{timer_ref: old_ref} = state(pid)

      GenServer.cast(pid, {:activate, @room_key})

      assert %{timer_ref: new_ref} = state(pid)
      assert new_ref != old_ref
      refute Process.read_timer(old_ref)
    end

    test "does not reset a syncing room", %{pid: pid} do
      GenServer.cast(pid, {:sync, @room_key})

      GenServer.cast(pid, {:activate, "another key"})

      assert %CargoRoom{pub_key: @room_key, status: :syncing} = state(pid)
    end
  end

  describe "mark_successful and complete" do
    test "mark_successful is ignored unless syncing", %{pid: pid} do
      GenServer.cast(pid, {:activate, @room_key})

      GenServer.cast(pid, :mark_successful)

      assert %CargoRoom{status: :pending, successful?: nil} = state(pid)
    end

    test "mark_successful flags a syncing room", %{pid: pid} do
      GenServer.cast(pid, {:sync, @room_key})

      GenServer.cast(pid, :mark_successful)

      assert %CargoRoom{status: :syncing, successful?: true} = state(pid)
    end

    test "complete is a no-op without a room", %{pid: pid} do
      GenServer.cast(pid, :complete)

      refute state(pid)
    end
  end

  describe "countdown timer" do
    test "drops the room and broadcasts when the countdown runs out", %{pid: pid} do
      GenServer.cast(pid, {:activate, @room_key})
      :sys.replace_state(pid, &%{&1 | timer: 1})

      send(pid, :update_timer)

      refute state(pid)
      assert_receive {:update_cargo_room, nil}
    end

    test "stops once syncing started", %{pid: pid} do
      GenServer.cast(pid, {:sync, @room_key})
      timer = state(pid).timer

      send(pid, :update_timer)

      assert %CargoRoom{status: :syncing, timer: ^timer} = state(pid)
    end
  end

  describe "sync timeout" do
    test "fails the syncing room it was set for", %{pid: pid} do
      GenServer.cast(pid, {:sync, @room_key})

      send(pid, {:sync_timeout, @room_key})

      assert %CargoRoom{status: :failed} = state(pid)
      assert_receive {:update_cargo_room, %CargoRoom{status: :failed}}
    end

    test "ignores timeout for another room", %{pid: pid} do
      GenServer.cast(pid, {:sync, @room_key})

      send(pid, {:sync_timeout, "another key"})

      assert %CargoRoom{status: :syncing} = state(pid)
    end
  end

  # Helpers

  defp state(pid), do: GenServer.call(pid, :get)
end
