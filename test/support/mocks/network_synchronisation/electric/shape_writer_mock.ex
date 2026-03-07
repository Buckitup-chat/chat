defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.ShapeWriterMock do
  @moduledoc "ShapeWriter mock for ShapeConsumer test"

  @spec write(atom(), atom(), term()) :: {:ok, term()} | {:error, atom()}
  def write(shape, op, value) do
    case Application.get_env(:chat, :consumer_test_pid) do
      pid when is_pid(pid) -> send(pid, {:write_called, shape, op, value})
      _ -> :ok
    end

    Application.get_env(:chat, :consumer_test_write_result, {:ok, :mock})
  end
end
