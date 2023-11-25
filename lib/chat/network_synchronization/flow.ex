defmodule Chat.NetworkSynchronization.Flow do
  @moduledoc "Synchronization worker flow"

  alias Chat.NetworkSynchronization.Status.CoolingStatus
  alias Chat.NetworkSynchronization.Status.ErrorStatus
  alias Chat.NetworkSynchronization.Status.SynchronizingStatus
  alias Chat.NetworkSynchronization.Status.UpdatingStatus

  alias Chat.NetworkSynchronization.Retrieval
  alias Chat.NetworkSynchronization.Store

  def start_half_cooled(source) do
    source
    |> make_half_cooled_status()
    |> update_mem_status(source.id)
  end

  def start_synchronization(source, ok: ok_action, error: error_action) do
    make_sync_status()
    |> update_mem_status(source.id)
    |> get_remote_keys(source.url)
    |> case do
      {:ok, remote_keys} ->
        diff = make_diff(remote_keys)

        diff
        |> make_updating_status()
        |> update_mem_status(source.id)
        |> then(&ok_action.(&1, diff))

      {:error, reason} ->
        make_error_status(reason)
        |> update_mem_status(source.id)
        |> then(error_action)
    end
  end

  def start_cooling(source) do
    source
    |> make_cooling_status()
    |> update_mem_status(source.id)
    |> finalize_update()
  end

  def start_key_retrieval(status, source, remote_key) do
    get_and_save(source.url, remote_key)

    status
    |> count_one_done()
    |> update_mem_status(source.id)
  end

  defp make_half_cooled_status(source), do: CoolingStatus.new_half(source)
  defp make_cooling_status(source), do: CoolingStatus.new(source)
  defp make_sync_status, do: SynchronizingStatus.new()
  defp make_error_status(reason), do: ErrorStatus.new(reason)
  defp make_updating_status(diff), do: UpdatingStatus.new(diff)
  defp count_one_done(status), do: UpdatingStatus.count_one_done(status)

  defp get_remote_keys(_status, api_url), do: Retrieval.remote_keys(api_url)
  defp make_diff(remote_keys), do: Retrieval.reject_known(remote_keys)
  defp get_and_save(api_url, remote_key), do: Retrieval.retrieve_key(api_url, remote_key)
  defp finalize_update(status), do: tap(status, fn _ -> Retrieval.finalize() end)

  defp update_mem_status(status, source_id),
    do: tap(status, &Store.update_source_status(source_id, &1))
end
