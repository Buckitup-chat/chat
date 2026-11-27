defmodule Chat.Db.Boot.ElectricReadyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Support.Rewire

  alias Chat.Db.Boot.ElectricReady

  defmodule NoProcess do
    @moduledoc "Hides every registered process; the rest delegates to `Process`."
    def whereis(_name), do: nil
    defdelegate info(pid, key), to: Process
  end

  rewire(ElectricReady, [{Process, NoProcess}, as: ElectricMissing])

  setup do
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: __MODULE__.Next})
    :ok
  end

  test "starts the next stage when Phoenix.Sync is alive" do
    assert Process.whereis(Phoenix.Sync.Supervisor)

    log =
      capture_log(fn ->
        start_supervised!({ElectricReady, next: next_stage()})
        assert_eventually(&next_stage_started?/0)
      end)

    refute log =~ "not found"
  end

  test "warns and still starts the next stage when Phoenix.Sync is not up yet" do
    log =
      capture_log(fn ->
        start_supervised!({ElectricMissing, next: next_stage()})
        assert_eventually(&next_stage_started?/0)
      end)

    assert log =~ "Phoenix.Sync.Supervisor not found"
  end

  test "is the last stage without next" do
    pid = start_supervised!({ElectricReady, next: nil})

    assert_eventually(fn -> match?({:messages, []}, Process.info(pid, :messages)) end)
    assert Process.alive?(pid)
    assert %{active: 0} = DynamicSupervisor.count_children(__MODULE__.Next)
  end

  defp next_stage, do: [under: __MODULE__.Next, run: [{Agent, fn -> :next end}]]
  defp next_stage_started?, do: DynamicSupervisor.count_children(__MODULE__.Next).active == 1

  defp assert_eventually(check, attempts \\ 100) do
    cond do
      check.() -> :ok
      attempts == 0 -> flunk("condition not met in time")
      true -> Process.sleep(10) && assert_eventually(check, attempts - 1)
    end
  end
end
