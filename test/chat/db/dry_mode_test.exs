defmodule Chat.Db.DryModeTest do
  use ExUnit.Case, async: true
  import Support.Rewire

  alias Chat.Db.ChangeTracker
  alias Chat.Db.Pipeline.Compactor
  alias Chat.Db.Pipeline.DryWriter
  alias Chat.Db.Pipeline.WriterProcess
  alias Chat.Db.WriteQueue

  defmodule NoSpaceMock do
    def db_free_space(_db), do: 0
  end

  defmodule PlentySpaceMock do
    def db_free_space(_db), do: 1024 * 1024 * 1024 * 1024
  end

  rewire(Chat.Db.Pipeline.Decider, [{Chat.Db.Maintenance, NoSpaceMock}, as: DryDecider])
  rewire(Chat.Db.Pipeline.Decider, [{Chat.Db.Maintenance, PlentySpaceMock}, as: WetDecider])

  describe "decider" do
    test "switches in dry mode when no space left" do
      context = start_pipeline_deps()

      {:ok, _} = DryDecider.start_link(decider_opts(context))

      assert Agent.get(context.relay, & &1)
      assert [DryWriter] = write_children(context)
    end

    @tag :tmp_dir
    test "starts writer and compactor when space is enough", %{tmp_dir: dir} do
      context = start_pipeline_deps()
      {:ok, db} = CubDB.start_link(data_dir: dir)

      {:ok, _} = WetDecider.start_link(decider_opts(context) |> Keyword.put(:db, db))

      refute Agent.get(context.relay, & &1)
      assert [Compactor, WriterProcess] = write_children(context) |> Enum.sort()
    end
  end

  describe "dry writer" do
    test "completes writing without storing anything" do
      queue = start_supervised!(WriteQueue)
      start_supervised!({DryWriter, name: nil, queue: queue})
      key = {:dry_mode_test, make_ref()}
      notify_when_written(key)
      WriteQueue.push({key, "value"}, queue)

      assert_receive {:written, ^key}
    end

    test "ignores deletes and mirrored payloads, keeps demanding" do
      queue = start_supervised!(WriteQueue)
      writer = start_supervised!({DryWriter, name: nil, queue: queue})
      key = {:dry_mode_test, make_ref()}
      notify_when_written(key)
      WriteQueue.set_mirrors([writer], queue)
      WriteQueue.mark_delete({:dry_mode_test, :gone}, queue)
      WriteQueue.push({key, "after delete"}, queue)

      assert_receive {:written, ^key}
      assert Process.alive?(writer)
    end

    test "write/2 and delete/2 cast the operation" do
      DryWriter.write(self(), [:a])
      DryWriter.delete(self(), [:b])

      assert_receive {:"$gen_cast", {:write, [:a]}}
      assert_receive {:"$gen_cast", {:delete, [:b]}}
    end
  end

  defp start_pipeline_deps do
    %{
      relay: start_supervised!({Agent, fn -> nil end}),
      supervisor: start_supervised!(DynamicSupervisor),
      queue: start_supervised!(WriteQueue)
    }
  end

  defp decider_opts(context) do
    [
      name: nil,
      db: :no_db,
      status_relay: context.relay,
      write_supervisor: context.supervisor,
      queue: context.queue,
      files_path: "unused",
      compactor: nil,
      writer: nil
    ]
  end

  defp write_children(context) do
    context.supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, _, _, [module]} -> module end)
  end

  defp notify_when_written(key) do
    test_pid = self()
    ChangeTracker.promise(key, fn -> send(test_pid, {:written, key}) end)
  end
end
