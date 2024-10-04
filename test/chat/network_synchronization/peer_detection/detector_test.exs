defmodule ChatTest.NetworkSynchronization.PeerDetection.DetectorTest do
  use ExUnit.Case, async: true
  import Rewire
  import ChatSupport.Utils, only: [await_till: 2]

  alias Chat.NetworkSynchronization.PeerDetection.LanDetector

  setup_all do
    start_supervised!(%{
      id: DetectorTestAgent,
      start: {Agent, :start_link, [fn -> %{} end, [name: DetectorTestAgent]]}
    })

    :ok
  end

  defmodule PubSubMock do
    def broadcast(_, _, message),
      do: Agent.update(DetectorTestAgent, &Map.put(&1, :broadcasted, message))
  end

  defmodule LanDetectionMock do
    def on_lan(_, _), do: Agent.update(DetectorTestAgent, &Map.put(&1, :lan_detection_ran, true))
  end

  rewire(LanDetector, [
    {Phoenix.PubSub, PubSubMock},
    {Chat.NetworkSynchronization.PeerDetection.LanDetection, LanDetectionMock}
  ])

  test "detector should work" do
    %{name: __MODULE__.Detector}
    |> start_detector
    |> assert_detector_started
    |> assert_restart_timer_set
    |> send_update
    |> send_range
    |> assert_lan_detection_ran
    |> assert_restart_timer_updated
    |> send_restart
    |> assert_restart_timer_updated
    |> stop_detector
  end

  defp send_update(context) do
    send(context.pid, :update)
    context
  end

  defp send_range(context) do
    send(context.pid, {:range, {"10.10.10.10", "255.255.255.0"}})
    context
  end

  defp send_restart(context) do
    send(context.pid, :restart)
    context
  end

  defp start_detector(context) do
    {:ok, pid} = start_supervised({LanDetector, name: context.name})
    context |> Map.put(:pid, pid)
  end

  defp stop_detector(context) do
    assert :ok = stop_supervised(LanDetector)
    context
  end

  defp assert_detector_started(context) do
    assert Process.alive?(context.pid)
    context
  end

  defp assert_restart_timer_set(context) do
    timer_ref = :sys.get_state(context.pid)
    time_left = Process.cancel_timer(timer_ref, async: false, info: true)
    assert time_left > :timer.minutes(70) - 100
    context |> Map.put(:timer_ref, timer_ref)
  end

  defp assert_lan_detection_ran(context) do
    await_till(fn -> Agent.get(DetectorTestAgent, &Map.get(&1, :lan_detection_ran)) end,
      step: 10,
      time: 500
    )
    |> tap(&refute :timeout == &1)

    context
  end

  defp assert_restart_timer_updated(context) do
    timer_ref = :sys.get_state(context.pid)
    time_left = Process.cancel_timer(timer_ref, async: false, info: true)
    assert time_left > :timer.minutes(70) - 50
    refute timer_ref == context.timer_ref
    context |> Map.put(:timer_ref, timer_ref)
  end
end
