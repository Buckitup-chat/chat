defmodule Chat.Sync.UsbDriveDumpRoomTest do
  use ExUnit.Case, async: false

  alias Chat.Identity
  alias Chat.Sync.UsbDriveDumpProgress
  alias Chat.Sync.UsbDriveDumpRoom
  alias Phoenix.PubSub

  @room_topic "chat::usb_drive_dump_room"
  @progress_topic "chat::usb_drive_dump_progress"

  setup do
    PubSub.subscribe(Chat.PubSub, @room_topic)
    PubSub.subscribe(Chat.PubSub, @progress_topic)

    {:ok, pid} = GenServer.start_link(UsbDriveDumpRoom, :ok)
    identity = Identity.create("Dump room")

    %{pid: pid, identity: identity, room_key: Identity.pub_key(identity)}
  end

  describe "public API on the named server" do
    test "get/0 and get_room_key/0 follow activate and remove" do
      identity = Identity.create("Named dump room")
      room_key = Identity.pub_key(identity)

      UsbDriveDumpRoom.remove()
      UsbDriveDumpRoom.activate(room_key, identity, 0)

      assert %UsbDriveDumpRoom{pub_key: ^room_key, status: :pending} = UsbDriveDumpRoom.get()
      assert ^room_key = UsbDriveDumpRoom.get_room_key()

      UsbDriveDumpRoom.mark_successful()
      UsbDriveDumpRoom.complete()

      assert %UsbDriveDumpRoom{status: :failed} = UsbDriveDumpRoom.get()

      UsbDriveDumpRoom.remove()

      refute UsbDriveDumpRoom.get()
      refute UsbDriveDumpRoom.get_room_key()
    end
  end

  describe "activate" do
    test "starts a pending room and broadcasts it", ctx do
      activate(ctx)

      assert %UsbDriveDumpRoom{status: :pending, pub_key: key, timer_ref: ref} = state(ctx.pid)
      assert key == ctx.room_key
      assert is_reference(ref)
      assert_receive {:update_usb_drive_dump_room, %UsbDriveDumpRoom{status: :pending}}
    end

    test "re-activation cancels the previous countdown timer", ctx do
      activate(ctx)
      %{timer_ref: old_ref} = state(ctx.pid)

      activate(ctx)

      assert %{timer_ref: new_ref} = state(ctx.pid)
      assert new_ref != old_ref
      refute Process.read_timer(old_ref)
    end

    test "does not reset a room that is dumping", ctx do
      dumping(ctx)
      other = Identity.create("Other room")

      GenServer.cast(ctx.pid, {:activate, Identity.pub_key(other), other, 0})

      assert %{status: :dumping, pub_key: key} = state(ctx.pid)
      assert key == ctx.room_key
    end
  end

  describe "get_room_key" do
    test "returns nil without a room and the key with one", ctx do
      refute GenServer.call(ctx.pid, :get_room_key)

      activate(ctx)

      assert GenServer.call(ctx.pid, :get_room_key) == ctx.room_key
    end
  end

  describe "progress" do
    test "set_total and update_progress track dumping", ctx do
      dumping(ctx)

      GenServer.cast(ctx.pid, {:set_total, 2, 200})
      GenServer.cast(ctx.pid, {:update_progress, 1, "a.jpg", 50})

      assert_receive {:update_usb_drive_dump_progress, %{progress: progress}}

      assert %UsbDriveDumpProgress{
               total_files: 2,
               total_size: 200,
               completed_size: 50,
               current_file: 1,
               current_filename: "a.jpg",
               percentage: 25
             } = progress
    end

    test "are ignored when not dumping", ctx do
      activate(ctx)

      GenServer.cast(ctx.pid, {:set_total, 2, 200})
      GenServer.cast(ctx.pid, {:update_progress, 1, "a.jpg", 50})

      assert %{progress: %UsbDriveDumpProgress{total_size: 0, completed_size: 0}} =
               state(ctx.pid)

      assert Process.alive?(ctx.pid)
    end
  end

  describe "complete" do
    test "is a no-op without a room", ctx do
      GenServer.cast(ctx.pid, :complete)

      refute state(ctx.pid)
    end

    test "marks successful dump as complete", ctx do
      dumping(ctx)

      GenServer.cast(ctx.pid, :mark_successful)
      GenServer.cast(ctx.pid, :complete)

      assert %{status: :complete, successful?: true} = state(ctx.pid)
      assert_receive {:update_usb_drive_dump_room, %{status: :complete}}
    end

    test "marks unsuccessful dump as failed", ctx do
      activate(ctx)

      GenServer.cast(ctx.pid, :mark_successful)
      GenServer.cast(ctx.pid, :complete)

      assert %{status: :failed, successful?: nil} = state(ctx.pid)
    end
  end

  describe "countdown timer" do
    test "ticks down while pending", ctx do
      activate(ctx)
      timer = state(ctx.pid).timer

      send(ctx.pid, :update_timer)

      assert %{timer: new_timer} = state(ctx.pid)
      assert new_timer == timer - 1
      assert_receive {:update_usb_drive_dump_progress, %UsbDriveDumpRoom{}}
    end

    test "drops the room when the countdown runs out", ctx do
      activate(ctx)
      :sys.replace_state(ctx.pid, &%{&1 | timer: 1})

      send(ctx.pid, :update_timer)

      refute state(ctx.pid)
      assert_receive {:update_usb_drive_dump_progress, nil}
    end

    test "stops once dumping started", ctx do
      dumping(ctx)
      timer = state(ctx.pid).timer

      send(ctx.pid, :update_timer)

      assert %{status: :dumping, timer: ^timer} = state(ctx.pid)
    end

    test "ignores ticks without a room", ctx do
      send(ctx.pid, :update_timer)

      refute state(ctx.pid)
      assert_receive {:update_usb_drive_dump_progress, nil}
    end
  end

  describe "dump timeout" do
    test "fails the dumping room it was set for", ctx do
      dumping(ctx)

      send(ctx.pid, {:dump_timeout, ctx.room_key})

      assert %{status: :failed} = state(ctx.pid)
      assert_receive {:update_usb_drive_dump_room, %{status: :failed}}
    end

    test "ignores timeout for another room", ctx do
      dumping(ctx)

      send(ctx.pid, {:dump_timeout, "other room key"})

      assert %{status: :dumping} = state(ctx.pid)
    end
  end

  # Helpers

  defp activate(%{pid: pid, room_key: key, identity: identity}),
    do: GenServer.cast(pid, {:activate, key, identity, 0})

  defp dumping(ctx) do
    activate(ctx)
    GenServer.cast(ctx.pid, :dump)
  end

  defp state(pid), do: GenServer.call(pid, :get)
end
