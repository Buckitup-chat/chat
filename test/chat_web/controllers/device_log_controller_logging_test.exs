defmodule ChatWebTest.Controllers.DeviceLogControllerLoggingTest do
  use ExUnit.Case, async: false
  import Rewire

  alias ChatWeb.DeviceLogController

  @pubsub_name ChatWebTest.Controllers.DeviceLogControllerLoggingTest.PubSubMock

  rewire(DeviceLogController, [
    {Chat.PubSub, ChatWebTest.Controllers.DeviceLogControllerLoggingTest.PubSubMock}
  ])

  test "incorrectly formatted device log message" do
    %{}
    |> setup_incorrect_message_responder
    |> request_device_log
    |> assert_incorrect_message_handled
  end

  test "weird formatted message" do
    %{}
    |> setup_weird_message_responder
    |> request_device_log
    |> assert_weird_message_handled
  end

  defp request_device_log(context) do
    fake_conn = Phoenix.ConnTest.build_conn()
    conn = DeviceLogController.log(fake_conn, %{})

    context
    |> Map.put(:response, conn)
  end

  defp assert_incorrect_message_handled(context) do
    assert context.response.resp_body =~ "Booting Linux on physical CPU 0x0000000000 [0x410fd083]"
    context
  end

  defp assert_weird_message_handled(context) do
    assert context.response.resp_body =~ "!!!!!"
    context
  end

  defp setup_incorrect_message_responder(context) do
    assert {:ok, _pid} = start_supervised({Phoenix.PubSub, name: @pubsub_name})
    pid = spawn(&responder/0)
    Process.sleep(100)
    assert pid |> Process.alive?()
    context
  end

  defp setup_weird_message_responder(context) do
    assert {:ok, _pid} = start_supervised({Phoenix.PubSub, name: @pubsub_name})
    spawn(&weird_responder/0)
    Process.sleep(100)
    context
  end

  defp responder do
    Phoenix.PubSub.subscribe(@pubsub_name, "chat->platform")

    receive_loop(fn ->
      Phoenix.PubSub.broadcast(
        @pubsub_name,
        "platform->chat",
        {:platform_response,
         {:device_log,
          {nil,
           [
             %{
               message: "Booting Linux on physical CPU 0x0000000000 [0x410fd083]",
               module: Logger,
               timestamp: {{1970, 1, 1}, {0, 0, 7, 600}},
               level: :info,
               metadata: [
                 index: 0,
                 erl_level: :info,
                 module: NervesLogging.KmsgTailer,
                 pid: "#PID<0.3003.0>",
                 time: 7_600_724,
                 gl: "#PID<0.2999.0>",
                 domain: [:elixir],
                 facility: :kernel
               ]
             }
           ]}}}
      )
    end)
  end

  defp receive_loop(action) do
    receive do
      :get_device_log ->
        action.()

      x ->
        x |> dbg()
        receive_loop(action)
    after
      1000 ->
        IO.write(";")
        receive_loop(action)
    end
  end

  defp weird_responder do
    Phoenix.PubSub.subscribe(@pubsub_name, "chat->platform")

    receive do
      :get_device_log ->
        Phoenix.PubSub.broadcast(
          @pubsub_name,
          "platform->chat",
          {:platform_response,
           {:device_log,
            {nil,
             [
               :unnknown_format_here
             ]}}}
        )
    end
  end
end
