defmodule Chat.NetworkSynchronization.Electric.ShapeConsumerBranchesTest do
  use ExUnit.Case, async: true, group: :ets_deferred

  import ExUnit.CaptureLog
  import Rewire
  import ChatSupport.Utils, only: [await_till: 2]

  alias Chat.NetworkSynchronization
  alias Chat.NetworkSynchronization.Electric.ShapeConsumer
  alias Chat.NetworkSynchronization.Status.ErrorStatus
  alias Chat.NetworkSynchronization.Status.LiveStatus
  alias Electric.Client.Message

  rewire(ShapeConsumer, [
    {Electric.Client, ChatSupport.Mocks.NetworkSynchronization.Electric.ElectricClientMock},
    {Chat.NetworkSynchronization.Electric.ShapeWriter,
     ChatSupport.Mocks.NetworkSynchronization.Electric.ShapeWriterMock},
    {Chat.Db, ChatSupport.Mocks.NetworkSynchronization.Electric.DbMock},
    {Chat.NetworkSynchronization.Electric.OffsetStore,
     ChatSupport.Mocks.NetworkSynchronization.Electric.OffsetStoreMock}
  ])

  @system_identifier "branches_system_id"

  setup do
    Application.put_env(:chat, :consumer_test_pid, self())
    Application.put_env(:chat, :electric_mock_messages, blocking_stream([]))
    Application.put_env(:chat, :consumer_test_repo_ready, true)
    Phoenix.PubSub.subscribe(Chat.PubSub, NetworkSynchronization.notification_topic())

    on_exit(fn ->
      Application.delete_env(:chat, :consumer_test_pid)
      Application.delete_env(:chat, :electric_mock_messages)
      Application.delete_env(:chat, :consumer_test_write_result)
      Application.delete_env(:chat, :consumer_test_repo_ready)
    end)

    %{peer_url: "http://10.9.#{System.unique_integer([:positive])}.1"}
  end

  describe "stream messages" do
    test "up_to_date goes live and unknown messages are ignored", %{peer_url: peer_url} do
      Application.put_env(
        :chat,
        :electric_mock_messages,
        blocking_stream([
          %Message.ControlMessage{control: :snapshot_end},
          %Message.ControlMessage{control: :up_to_date}
        ])
      )

      consumer = start_consumer!(peer_url)

      assert_receive {:admin, {:electric_sync_status, ^peer_url, :user_card, %LiveStatus{}}}, 500
      assert {_, _, _, {_pid, _ref}, 1_000, nil} = :sys.get_state(consumer)
    end

    test "read session block waits for approval before retrying", %{peer_url: peer_url} do
      Application.put_env(
        :chat,
        :electric_mock_messages,
        Stream.map([:boom], fn _ ->
          raise %Electric.Client.Error{message: "blocked", resp: {:read_session, "pending"}}
        end)
      )

      capture_log(fn ->
        consumer = start_consumer!(peer_url)

        assert_receive {:admin,
                        {:electric_sync_status, ^peer_url, :user_card,
                         %ErrorStatus{reason: "awaiting approval: pending"}}},
                       1_000

        assert {_, _, _, nil, 30_000, restart_ref} = :sys.get_state(consumer)
        assert is_reference(restart_ref)
      end)
    end
  end

  describe "write results" do
    test "other write error is logged and skipped", %{peer_url: peer_url} do
      Application.put_env(:chat, :consumer_test_write_result, {:error, :bad_row})
      consumer = start_consumer!(peer_url)
      {_, _, _, task_info, _, _} = :sys.get_state(consumer)

      log = capture_log(fn -> write_change(consumer) end)

      assert log =~ "write failed (:bad_row), skipping"
      assert {_, _, _, ^task_info, 1_000, nil} = :sys.get_state(consumer)
    end

    test "repo not available with a reason cancels the stream and logs it", %{peer_url: peer_url} do
      [
        {%{message: "pool down"}, "pool down"},
        {%File.Error{reason: :enoent, action: "read", path: "db"},
         ~s(could not read "db": no such file or directory)},
        {"plain reason", "plain reason"},
        {{:shutdown, :repo}, "{:shutdown, :repo}"}
      ]
      |> Enum.each(fn {reason, expected} ->
        Application.put_env(
          :chat,
          :consumer_test_write_result,
          {:error, {:repo_not_available, reason}}
        )

        url = "#{peer_url}/#{System.unique_integer([:positive])}"
        consumer = start_consumer!(url)
        {_, _, _, {task_pid, _}, _, _} = :sys.get_state(consumer)

        log = capture_log(fn -> write_change(consumer) end)

        assert log =~ "repo not available (#{expected})"
        assert {_, _, _, nil, 2_000, restart_ref} = :sys.get_state(consumer)
        assert is_reference(restart_ref)
        refute Process.alive?(task_pid)
      end)
    end
  end

  describe "restart and refetch" do
    test "restart_stream is ignored while a stream is running", %{peer_url: peer_url} do
      consumer = start_consumer!(peer_url)
      state = :sys.get_state(consumer)

      send(consumer, :restart_stream)

      assert state == :sys.get_state(consumer)
    end

    test "restart_stream launches the stream once the repo is ready", %{peer_url: peer_url} do
      Application.put_env(:chat, :consumer_test_repo_ready, false)
      consumer = start_consumer!(peer_url)
      assert {_, _, _, nil, 2_000, _restart_ref} = :sys.get_state(consumer)

      Application.put_env(:chat, :consumer_test_repo_ready, true)
      send(consumer, :restart_stream)

      assert {_, _, _, {task_pid, _ref}, 2_000, nil} = :sys.get_state(consumer)
      assert Process.alive?(task_pid)
    end

    test "must_refetch kills the running stream and starts a new one", %{peer_url: peer_url} do
      consumer = start_consumer!(peer_url)
      {_, _, _, {old_pid, _}, _, _} = :sys.get_state(consumer)

      send(consumer, :must_refetch)

      assert_receive :offset_deleted, 500
      assert {_, _, _, {new_pid, _}, 1_000, nil} = :sys.get_state(consumer)
      refute Process.alive?(old_pid)
      assert Process.alive?(new_pid)
    end

    test "must_refetch cancels a pending restart", %{peer_url: peer_url} do
      Application.put_env(:chat, :consumer_test_repo_ready, false)
      consumer = start_consumer!(peer_url)
      {_, _, _, nil, _, restart_ref} = :sys.get_state(consumer)

      Application.put_env(:chat, :consumer_test_repo_ready, true)
      send(consumer, :must_refetch)

      assert_receive :offset_deleted, 500
      assert {_, _, _, {_pid, _ref}, 1_000, nil} = :sys.get_state(consumer)
      refute Process.read_timer(restart_ref)
    end
  end

  describe "process lifecycle" do
    test "stale DOWN and unknown messages leave the state unchanged", %{peer_url: peer_url} do
      consumer = start_consumer!(peer_url)
      state = :sys.get_state(consumer)

      send(consumer, {:DOWN, make_ref(), :process, self(), :gone})
      send(consumer, :unexpected)

      assert state == :sys.get_state(consumer)
    end

    test "terminate kills the stream and cancels a pending restart", %{peer_url: peer_url} do
      {:ok, running} = start_unsupervised(peer_url)
      {_, _, _, {task_pid, _}, _, _} = :sys.get_state(running)

      Application.put_env(:chat, :consumer_test_repo_ready, false)
      {:ok, waiting} = start_unsupervised("#{peer_url}/waiting")
      {_, _, _, nil, _, restart_ref} = :sys.get_state(waiting)

      :ok = GenServer.stop(running)
      :ok = GenServer.stop(waiting)

      refute Process.alive?(task_pid)
      refute Process.read_timer(restart_ref)
    end
  end

  # Helpers

  defp blocking_stream(messages) do
    Stream.concat(messages, Stream.repeatedly(fn -> Process.sleep(:infinity) end))
  end

  defp start_consumer!(peer_url) do
    consumer =
      start_supervised!(
        {ShapeConsumer,
         peer_url: peer_url, system_identifier: @system_identifier, shape: :user_card},
        id: peer_url
      )

    await_till(fn -> :sys.get_state(consumer) |> elem(3) != nil end, time: 300, step: 20)
    consumer
  end

  defp start_unsupervised(peer_url) do
    ShapeConsumer.start_link(
      peer_url: peer_url,
      system_identifier: @system_identifier,
      shape: :user_card
    )
  end

  defp write_change(consumer) do
    send(consumer, {:change, :insert, :row})
    assert_receive {:write_called, :user_card, :insert, :row, _opts}, 500
  end
end
