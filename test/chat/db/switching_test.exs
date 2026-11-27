defmodule Chat.Db.SwitchingTest do
  use ExUnit.Case, async: false

  alias Chat.Db.Common
  alias Chat.Db.Switching
  alias Chat.Db.WriteQueue

  require WriteQueue

  @source Chat.Db.SwitchingTest.Source
  @target Chat.Db.SwitchingTest.Target
  @other Chat.Db.SwitchingTest.Other

  @queues [
    Chat.Db.SwitchingTest.Source.Queue,
    Chat.Db.SwitchingTest.Target.Queue,
    Chat.Db.SwitchingTest.Other.Queue
  ]

  setup do
    Enum.each(@queues, &start_supervised!({WriteQueue, name: &1}, id: &1))
  end

  describe "mirror/2" do
    test "sends source writes to the target writer and stops target mirroring" do
      Switching.mirror(@source, @target)

      assert mirrors(@source) == [Chat.Db.SwitchingTest.Target.Writer]
      assert mirrors(@target) == nil
    end

    test "sends source writes to every target writer" do
      Switching.mirror(@source, [@target, @other])

      assert mirrors(@source) == [
               Chat.Db.SwitchingTest.Target.Writer,
               Chat.Db.SwitchingTest.Other.Writer
             ]

      assert mirrors(@target) == nil
      assert mirrors(@other) == nil
    end

    test "is a no-op for a target whose queue is not running" do
      assert :ok = Switching.mirror(@source, Chat.Db.SwitchingTest.Gone)
      assert mirrors(@source) == [Chat.Db.SwitchingTest.Gone.Writer]
    end
  end

  test "unmirror/1 stops mirroring the source" do
    Switching.mirror(@source, @target)

    Switching.unmirror(@source)

    assert mirrors(@source) == nil
  end

  test "set_default/1 points the data env at the given db" do
    saved = Map.new([:data_queue, :data_pid, :data_dry], &{&1, Application.get_env(:chat, &1)})

    on_exit(fn ->
      Enum.each(saved, fn {key, value} -> Application.put_env(:chat, key, value) end)
    end)

    Switching.set_default(@target)

    assert Application.get_env(:chat, :data_queue) == Chat.Db.SwitchingTest.Target.Queue
    assert Application.get_env(:chat, :data_pid) == @target
    assert Application.get_env(:chat, :data_dry) == Chat.Db.SwitchingTest.Target.DryStatus
  end

  defp mirrors(db) do
    db
    |> Common.names(:queue)
    |> :sys.get_state()
    |> WriteQueue.q_state(:mirrors)
  end
end
