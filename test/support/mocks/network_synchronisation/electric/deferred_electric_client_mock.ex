defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.DeferredElectricClientMock do
  @moduledoc """
  Mock for Electric.Client used in DeferredStore refetch tests.

  Captures the endpoint and stream arguments, sends them to the test process,
  then returns a finite stream of configured messages.
  """

  alias Electric.Client.Message

  def new!(opts) when is_list(opts) do
    notify({:client_created, opts[:endpoint]})
    {:mock_client, opts[:endpoint]}
  end

  def stream({:mock_client, endpoint}, queryable, opts) do
    notify({:stream_called, endpoint, queryable, opts})
    Application.get_env(:chat, :deferred_mock_messages, [])
  end

  defp notify(msg) do
    case Application.get_env(:chat, :deferred_test_pid) do
      pid when is_pid(pid) -> send(pid, msg)
      _ -> :ok
    end
  end

  def change_message(shape_module, attrs) do
    struct = struct!(shape_module, attrs)
    %Message.ChangeMessage{headers: %{operation: :insert}, value: struct}
  end
end
