defmodule Chat.NetworkSynchronization.WorkerTest do
  use ExUnit.Case, async: true
  import Rewire
  import ChatSupport.Utils, only: [await_till: 2]

  alias Chat.NetworkSynchronization.Source
  alias Chat.NetworkSynchronization.Status
  alias Chat.NetworkSynchronization.Worker

  rewire(Worker, [
    {Chat.NetworkSynchronization.Flow, ChatSupport.Mocks.NetworkSynchronization.FlowMockForWorker}
  ])

  test "full worker flow" do
    %{name: __MODULE__.Worker}
    |> make_failing_source
    |> start_worker
    |> assert_error_status
    |> retry
    |> assert_error_status
    |> stop_worker
    |> fix_source
    |> start_worker_deferred
    |> assert_cooling
    |> finish_cooling
    |> assert_updating
    |> assert_cooling
    |> finish_cooling
    |> assert_updating
    |> stop_worker
  end

  defp make_failing_source(context) do
    source =
      Source.new(1)
      |> struct(url: "bad url")

    context |> Map.put(:source, source)
  end

  defp start_worker(context) do
    assert {:ok, pid} = start_supervised({Worker, source: context.source, name: context.name})
    context |> Map.put(:pid, pid)
  end

  defp start_worker_deferred(context) do
    assert {:ok, pid} =
             start_supervised(
               {Worker, source: context.source, name: context.name, deferred: true}
             )

    context |> Map.put(:pid, pid)
  end

  defp stop_worker(context) do
    assert :ok = stop_supervised(Worker)
    context
  end

  defp retry(context) do
    send(context.pid, :synchronise)
    context
  end

  defp fix_source(context) do
    context.source
    |> struct(url: "http://example.net")
    |> then(&Map.put(context, :source, &1))
  end

  defp finish_cooling(context) do
    send(context.pid, :synchronise)
    context
  end

  defp assert_error_status(context) do
    await_worker_status(context.pid, Status.ErrorStatus, 500)
    context
  end

  defp assert_cooling(context) do
    await_worker_status(context.pid, Status.CoolingStatus, 500)
    context
  end

  defp assert_updating(context) do
    await_worker_status(context.pid, Status.UpdatingStatus, 500)
    context
  end

  defp await_worker_status(pid, status, time) do
    refute :timeout ==
             await_till(
               fn ->
                 status == get_status(pid) |> Map.get(:__struct__)
               end,
               time: time,
               step: 100
             )
  end

  defp get_status(pid) do
    :sys.get_state(pid)
    |> case do
      {_source, status, _keys} -> status
      _ -> :error
    end
  end
end
