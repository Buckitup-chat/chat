defmodule Chat.Storage.PlanRunnerTest do
  use Chat.Test.PgPairCase, mode: :committed, async: false

  import Chat.Storage.Link, only: [~>: 2]

  alias Chat.Data.Schemas.UserCard
  alias Chat.Storage.LinkRunner
  alias Chat.Storage.Links
  alias Chat.Storage.PlanRunner
  alias Chat.Test.PgPair.Files
  alias Chat.Test.PgPairHelper.Db

  @moduletag :capture_log

  setup do
    on_exit(fn -> :ets.delete_all_objects(Links) end)
  end

  describe "LinkRunner" do
    test "stopping the runner tears the link down", %{unit_a: a, unit_b: b} do
      runner = start_supervised!({LinkRunner, link: a ~> b, lag_ms: 20})

      assert :ok = LinkRunner.replicate(runner)
      Process.sleep(60)
      assert {:ok, %{status: :replicating, lag_bytes: lag}} = Links.get({:main, :backup})
      assert is_integer(lag)

      stop_supervised!(LinkRunner)

      refute slot?("backup_from_main")
      assert :stopped == Links.status({:main, :backup})
    end
  end

  describe "plan" do
    test "runs every step in order", %{unit_a: a, unit_b: b} do
      Files.user_card!(UnitARepo)
      test = self()

      plan = [
        {:bootstrap, a ~> b},
        {:replicate, a ~> b},
        {:await, [a ~> b], :chunks},
        {:stop, a ~> b},
        {:switch_default, b},
        :eject
      ]

      runner =
        start_supervised!(
          {PlanRunner,
           plan: plan,
           switch_default: &send(test, {:switched, &1}),
           eject: fn -> send(test, :ejected) end}
        )

      assert_receive {:switched, ^b}
      assert_receive :ejected

      assert %{status: :done, results: results} = PlanRunner.info(runner)

      assert [:ok, :ok, :ok, :ok, {:switched, b}, :ejected] ==
               for({_step, result} <- results, do: result)

      assert 1 == UnitBRepo.aggregate(UserCard, :count)
      refute slot?("backup_from_main")
    end

    test "halts on an error and stops the links it runs", %{unit_a: a, unit_b: b} do
      plan = [{:replicate, a ~> b}, {:switch_default, b}, :eject]
      runner = start_supervised!({PlanRunner, plan: plan})

      assert %{status: {:halted, {:switch_default, ^b}, {:no_callback, :switch_default}}} =
               await_info(runner, &match?({:halted, _, _}, &1.status))

      assert slot?("backup_from_main")
      stop_supervised!(PlanRunner)
      refute slot?("backup_from_main")
    end

    test "ignores messages its steps did not take", %{unit_a: a} do
      parent = self()
      eject = fn -> send(self(), {:stray, :reply}) |> then(fn _ -> send(parent, :ejected) end) end
      runner = start_supervised!({PlanRunner, plan: [:eject, {:switch_default, a}], eject: eject})

      assert_receive :ejected
      assert %{status: {:halted, _, _}} = await_info(runner, &match?({:halted, _, _}, &1.status))
      assert Process.alive?(runner)
    end
  end

  defp await_info(runner, done?, attempts \\ 100) do
    info = PlanRunner.info(runner)

    if done?.(info) or attempts == 0,
      do: info,
      else: Process.sleep(20) |> then(fn _ -> await_info(runner, done?, attempts - 1) end)
  end

  defp slot?(name) do
    UnitARepo
    |> Db.rows("SELECT 1 FROM pg_replication_slots WHERE slot_name = $1", [name])
    |> Enum.any?()
  end
end
