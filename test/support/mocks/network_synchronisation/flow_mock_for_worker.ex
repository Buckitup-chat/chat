defmodule ChatSupport.Mocks.NetworkSynchronization.FlowMockForWorker do
  @moduledoc "Mocking network synchronization flow for Worker test"
  alias Chat.NetworkSynchronization.Status

  def start_half_cooled(source), do: Status.CoolingStatus.new_half(source)
  def start_cooling(source), do: Status.CoolingStatus.new(source)

  def start_synchronization(source, ok: ok_action, error: error_action) do
    case source.url do
      "bad url" ->
        Status.ErrorStatus.new("URL is unreachable")
        |> then(error_action)

      _ ->
        keys = [1, 2, 3, 4]

        keys
        |> Status.UpdatingStatus.new()
        |> then(&ok_action.(&1, keys))
    end
  end

  def start_key_retrieval(status, _source, _remote_key) do
    Process.sleep(50)
    Status.UpdatingStatus.count_one_done(status)
  end
end
