defmodule ChatTest.NetworkSynchronization.SupervisionTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.NetworkSynchronization
  alias Chat.NetworkSynchronization.Store

  rewire(Store, source_db_prefix: S5, source_table: S5, status_table: T5)
  rewire(Store, source_db_prefix: S5, source_table: S5, status_table: T5, as: StoreMock)

  rewire(NetworkSynchronization,
    Store: StoreMock,
    Worker: WorkerMock,
    registry: R5,
    dynamic_supervisor: D5,
    as: NetworkSynchronizationMock
  )

  rewire(Chat.NetworkSynchronization.Flow,
    NetworkSynchronization: NetworkSynchronizationMock,
    as: FlowMock
  )

  rewire(Chat.NetworkSynchronization.Worker, [
    {Chat.NetworkSynchronization.Flow, FlowMock},
    {:as, WorkerMock}
  ])

  rewire(NetworkSynchronization,
    Store: StoreMock,
    Worker: WorkerMock,
    registry: R5,
    dynamic_supervisor: D5
  )

  test "supervision" do
    %{dynamic: D5, registry: R5}
    |> start_supervisor()
    |> create_started_sources()
    |> init_workers()
    |> assert_workers_alive()
    |> stop_one_worker()
    |> assert_one_worker_stopped()
    |> start_stopped_worker()
    |> assert_workers_alive()
    |> stop_supervisor()
  end

  defp create_started_sources(context) do
    Store.init()

    for i <- 1..3 do
      Store.add_source()
      |> struct(url: "bad url #{i}}", started?: true)
      |> Store.update_source()
    end

    context
  end

  defp init_workers(context) do
    NetworkSynchronization.init_workers()
    context
  end

  defp stop_one_worker(context) do
    id =
      NetworkSynchronization.synchronisation()
      |> Enum.find(fn {source, _} -> source.started? end)
      |> elem(0)
      |> Map.get(:id)

    NetworkSynchronization.stop_source(id)

    context |> Map.put(:stopped_source_id, id)
  end

  defp start_stopped_worker(context) do
    NetworkSynchronization.start_source(context.stopped_source_id)
    context
  end

  defp start_supervisor(context) do
    assert {:ok, pid} =
             start_supervised(
               {Chat.NetworkSynchronization.Supervisor,
                name: S5, dynamic_name: context.dynamic, registry_name: context.registry}
             )

    context |> Map.put(:supervisor_pid, pid)
  end

  defp stop_supervisor(context) do
    stop_supervised(Supervisor)
    context
  end

  defp assert_workers_alive(context) do
    assert context.supervisor_pid |> Process.alive?()
    assert context.dynamic |> Process.whereis() |> Process.alive?()
    assert context.dynamic |> DynamicSupervisor.count_children() |> Map.get(:active) > 0

    NetworkSynchronization.synchronisation()
    |> Enum.filter(fn {source, _} -> source.started? end)
    |> Enum.each(fn {source, _} ->
      assert [{pid, _}] = Registry.lookup(context.registry, source.id)
      assert Process.alive?(pid)
    end)

    Process.sleep(50)

    NetworkSynchronization.synchronisation()
    |> Enum.each(fn {source, status} ->
      refute source.started? and is_nil(status)
    end)

    context
  end

  defp assert_one_worker_stopped(context) do
    assert [] == Registry.lookup(context.registry, context.stopped_source_id)

    NetworkSynchronization.synchronisation()
    |> Enum.filter(fn {source, _} -> source.id == context.stopped_source_id end)
    |> Enum.each(fn {source, status} ->
      refute source.started?
      refute status
    end)

    context
  end
end
