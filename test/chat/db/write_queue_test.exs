defmodule Chat.Db.WriteQueueTest do
  use ExUnit.Case, async: true

  import Chat.Db.WriteQueue.ReadStream, only: [read_stream_new: 2]

  alias Chat.Db.ChangeTracker
  alias Chat.Db.WriteQueue

  setup do
    %{queue: start_supervised!(WriteQueue)}
  end

  test "empty and value-less items skip the queue", %{queue: queue} do
    key = {:write_queue_test, make_ref()}
    notify_when_written(key)

    assert :ok = WriteQueue.push({nil, nil}, queue)
    assert :ok = WriteQueue.put({nil, nil}, queue)
    assert :ok = WriteQueue.put_chunk({nil, nil}, queue)
    WriteQueue.push({key, nil}, queue)
    WriteQueue.put({key, nil}, queue)
    WriteQueue.put_chunk({key, nil}, queue)

    assert_receive {:written, ^key}
    WriteQueue.demand(queue)
    refute_receive {:"$gen_cast", _}, 50
  end

  test "data goes to consumer before deletes and logs", %{queue: queue} do
    WriteQueue.put({:log, 1}, queue)
    WriteQueue.mark_delete(:gone, queue)
    WriteQueue.push({:data, 1}, queue)

    assert [{:write, [{:data, 1}]}, {:delete, [:gone]}, {:write, [{:log, 1}]}] =
             1..3 |> Enum.map(fn _ -> demand_payload(queue) end)
  end

  test "second chunk waits until the first one is consumed", %{queue: queue} do
    assert :ok = WriteQueue.put_chunk({:chunk, 1}, queue)
    waiting = Task.async(fn -> WriteQueue.put_chunk({:chunk, 2}, queue) end)

    refute Task.yield(waiting, 50)

    assert {:write, [{:chunk, 1}]} = demand_payload(queue)
    assert :ok = Task.await(waiting)
    assert {:write, [{:chunk, 2}]} = demand_payload(queue)
  end

  test "second stream is ignored unless forced", %{queue: queue} do
    stream = read_stream_new(:no_db, [])

    assert :ok = WriteQueue.put_stream(stream, queue)
    assert :ignored = WriteQueue.put_stream(stream, queue)
    assert :ok = WriteQueue.force_stream(stream, queue)
  end

  test "dead consumer is dropped and data is kept for the next one", %{queue: queue} do
    Task.async(fn -> WriteQueue.demand(queue) end) |> Task.await()

    WriteQueue.push({:data, :kept}, queue)

    assert {:write, [{:data, :kept}]} = demand_payload(queue)
  end

  test "payload is mirrored to every mirror", %{queue: queue} do
    test_pid = self()
    mirror = spawn_link(fn -> forward_mirrored(test_pid) end)

    WriteQueue.set_mirrors([mirror], [queue])
    WriteQueue.push({:data, :mirrored}, queue)

    assert {:write, [{:data, :mirrored}]} = demand_payload(queue)
    assert_receive {:mirrored, {:write, [{:data, :mirrored}]}}
  end

  defp demand_payload(queue) do
    WriteQueue.demand(queue)
    assert_receive {:"$gen_cast", payload}
    payload
  end

  defp forward_mirrored(test_pid) do
    receive do
      {:"$gen_cast", {:mirror, payload}} -> send(test_pid, {:mirrored, payload})
    end
  end

  defp notify_when_written(key) do
    test_pid = self()
    ChangeTracker.promise(key, fn -> send(test_pid, {:written, key}) end)
  end
end
