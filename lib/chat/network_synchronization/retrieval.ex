defmodule Chat.NetworkSynchronization.Retrieval do
  @moduledoc "Data retrieval"

  alias Chat.Db.NetworkSync
  alias Chat.Sync.DbBrokers

  def remote_keys(url) do
    NetworkSync.load_atoms()
    {:ok, NetworkSync.get_keys(url)}
  rescue
    e ->
      e |> dbg()
      {:error, e |> inspect()}
  end

  def reject_know(keys), do: NetworkSync.reject_known(keys)

  def retrieve_key(url, remote_key), do: NetworkSync.get_value(remote_key, url)

  def finalize do
    DbBrokers.refresh()
  end
end
