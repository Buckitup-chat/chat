defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.OffsetStoreMock do
  @moduledoc "OffsetStore mock for ShapeConsumer test — stores offsets in the test process"

  def save(_peer_url, _shape, resume) do
    notify({:offset_saved, resume})
  end

  def load(_peer_url, _shape), do: nil

  def delete(_peer_url) do
    notify(:offset_deleted)
  end

  def delete(_peer_url, _shape) do
    notify(:offset_deleted)
  end

  defp notify(msg) do
    case Application.get_env(:chat, :consumer_test_pid) do
      pid when is_pid(pid) -> send(pid, msg)
      _ -> :ok
    end
  end
end
