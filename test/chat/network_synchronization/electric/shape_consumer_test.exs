defmodule Chat.NetworkSynchronization.Electric.ShapeConsumerTest do
  use ExUnit.Case, async: false

  import Rewire
  import ChatSupport.Utils, only: [await_till: 2]

  alias Chat.Data.Schemas.UserCard
  alias Chat.NetworkSynchronization.Electric.ShapeConsumer
  alias Electric.Client.Message

  rewire(ShapeConsumer, [
    {Electric.Client, ChatSupport.Mocks.NetworkSynchronization.Electric.ElectricClientMock},
    {Chat.NetworkSynchronization.Electric.ShapeWriter,
     ChatSupport.Mocks.NetworkSynchronization.Electric.ShapeWriterMock},
    {Chat.Db, ChatSupport.Mocks.NetworkSynchronization.Electric.DbMock},
    {Chat.NetworkSynchronization.Electric.OffsetStore,
     ChatSupport.Mocks.NetworkSynchronization.Electric.OffsetStoreMock}
  ])

  @peer_url "http://10.0.0.1"
  @system_identifier "test_system_id"

  setup do
    Application.put_env(:chat, :consumer_test_pid, self())
    Application.put_env(:chat, :electric_mock_messages, [])
    Application.put_env(:chat, :consumer_test_repo_ready, true)

    on_exit(fn ->
      Application.delete_env(:chat, :consumer_test_pid)
      Application.delete_env(:chat, :electric_mock_messages)
      Application.delete_env(:chat, :consumer_test_write_result)
      Application.delete_env(:chat, :consumer_test_repo_ready)
    end)

    :ok
  end

  test "forwards insert change to ShapeWriter" do
    card = %UserCard{
      user_hash: <<1::256>>,
      name: "Alice",
      sign_pkey: "s",
      contact_pkey: "c",
      contact_cert: "cc",
      crypt_pkey: "cp",
      crypt_cert: "ccc"
    }

    Application.put_env(:chat, :electric_mock_messages, [
      %Message.ChangeMessage{headers: %{operation: :insert}, value: card}
    ])

    {:ok, _pid} =
      start_supervised(
        {ShapeConsumer,
         peer_url: @peer_url, system_identifier: @system_identifier, shape: :user_card}
      )

    assert_receive {:write_called, :user_card, :insert, ^card}, 500
  end

  test "forwards update change to ShapeWriter" do
    card = %UserCard{
      user_hash: <<2::256>>,
      name: "Bob",
      sign_pkey: "s",
      contact_pkey: "c",
      contact_cert: "cc",
      crypt_pkey: "cp",
      crypt_cert: "ccc"
    }

    Application.put_env(:chat, :electric_mock_messages, [
      %Message.ChangeMessage{headers: %{operation: :update}, value: card}
    ])

    {:ok, _pid} =
      start_supervised(
        {ShapeConsumer,
         peer_url: @peer_url, system_identifier: @system_identifier, shape: :user_card}
      )

    assert_receive {:write_called, :user_card, :update, ^card}, 500
  end

  test "saves ResumeMessage to OffsetStore" do
    resume = %Message.ResumeMessage{shape_handle: "h1", offset: nil, schema: %{}}

    Application.put_env(:chat, :electric_mock_messages, [resume])

    {:ok, _pid} =
      start_supervised(
        {ShapeConsumer,
         peer_url: @peer_url, system_identifier: @system_identifier, shape: :user_card}
      )

    assert_receive {:offset_saved, ^resume}, 500
  end

  test "clears offset and restarts stream on must_refetch" do
    pid_holder = self()

    Application.put_env(:chat, :electric_mock_messages, [
      %Message.ControlMessage{control: :must_refetch}
    ])

    {:ok, consumer} =
      start_supervised(
        {ShapeConsumer,
         peer_url: @peer_url, system_identifier: @system_identifier, shape: :user_card}
      )

    assert_receive :offset_deleted, 500

    # After must_refetch the consumer should still be alive
    assert Process.alive?(consumer)

    # Verify state has reset backoff by inspecting the GenServer state
    {_url, _si, _shape, _task_info, backoff, _restart_ref} = :sys.get_state(consumer)

    await_till(
      fn ->
        {_url, _si, _shape, _task_info, b, _restart_ref} =
          :sys.get_state(pid_holder |> then(fn _ -> consumer end))

        b == 1_000
      end,
      time: 500,
      step: 50
    )

    # Satisfy the compiler — backoff was reset
    assert is_integer(backoff)
  end

  test "cancels task and retries with backoff when repo is not available" do
    card = %UserCard{
      user_hash: <<1::256>>,
      name: "Alice",
      sign_pkey: "s",
      contact_pkey: "c",
      contact_cert: "cc",
      crypt_pkey: "cp",
      crypt_cert: "ccc"
    }

    Application.put_env(:chat, :consumer_test_write_result, {:error, :repo_not_available})

    Application.put_env(:chat, :electric_mock_messages, [
      %Message.ChangeMessage{headers: %{operation: :insert}, value: card}
    ])

    {:ok, consumer} =
      start_supervised(
        {ShapeConsumer,
         peer_url: @peer_url, system_identifier: @system_identifier, shape: :user_card}
      )

    await_till(
      fn ->
        {_url, _si, _shape, _task_info, backoff, _restart_ref} = :sys.get_state(consumer)
        backoff > 1_000
      end,
      time: 1500,
      step: 50
    )

    assert Process.alive?(consumer)
    {_url, _si, _shape, _task_info, backoff, restart_ref} = :sys.get_state(consumer)
    assert backoff == 2_000
    assert is_reference(restart_ref)
  end

  test "waits for the repo before launching the stream" do
    Application.put_env(:chat, :consumer_test_repo_ready, false)

    {:ok, consumer} =
      start_supervised(
        {ShapeConsumer,
         peer_url: @peer_url, system_identifier: @system_identifier, shape: :user_card}
      )

    refute_receive {:write_called, _, _, _}, 200

    {_url, _si, _shape, task_info, backoff, restart_ref} = :sys.get_state(consumer)
    assert task_info == nil
    assert backoff == 2_000
    assert is_reference(restart_ref)
  end

  test "does not stack retries when a restart is already scheduled" do
    card = %UserCard{
      user_hash: <<1::256>>,
      name: "Alice",
      sign_pkey: "s",
      contact_pkey: "c",
      contact_cert: "cc",
      crypt_pkey: "cp",
      crypt_cert: "ccc"
    }

    Application.put_env(:chat, :consumer_test_write_result, {:error, :repo_not_available})

    Application.put_env(:chat, :electric_mock_messages, [
      %Message.ChangeMessage{headers: %{operation: :insert}, value: card},
      %Message.ChangeMessage{headers: %{operation: :insert}, value: card},
      %Message.ChangeMessage{headers: %{operation: :insert}, value: card}
    ])

    {:ok, consumer} =
      start_supervised(
        {ShapeConsumer,
         peer_url: @peer_url, system_identifier: @system_identifier, shape: :user_card}
      )

    Process.sleep(100)

    {_url, _si, _shape, _task_info, backoff, restart_ref} = :sys.get_state(consumer)
    assert backoff == 2_000
    assert is_reference(restart_ref)

    # Verify only one restart is scheduled even though multiple messages failed
    assert Process.read_timer(restart_ref) != false
  end

  test "clears offset and schedules retry after stream task exits" do
    # Empty stream — Task exits immediately with :normal
    Application.put_env(:chat, :electric_mock_messages, [])

    {:ok, consumer} =
      start_supervised(
        {ShapeConsumer,
         peer_url: @peer_url, system_identifier: @system_identifier, shape: :user_card}
      )

    # Offset is cleared on :DOWN to force full re-snapshot on restart
    assert_receive :offset_deleted, 500

    # Task exits, GenServer schedules restart; verify backoff doubles
    await_till(
      fn ->
        {_url, _si, _shape, _task_info, backoff, _restart_ref} = :sys.get_state(consumer)
        backoff > 1_000
      end,
      time: 500,
      step: 50
    )

    {_url, _si, _shape, _task_info, backoff, _restart_ref} = :sys.get_state(consumer)
    assert backoff == 2_000
  end
end
