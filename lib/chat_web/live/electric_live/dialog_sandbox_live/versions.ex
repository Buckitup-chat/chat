defmodule ChatWeb.ElectricLive.DialogSandboxLive.Versions do
  @moduledoc "Version history of a message: expanding, caching and refreshing it."

  import ChatWeb.LiveHelpers, only: [public_url: 1]
  import Phoenix.Component, only: [assign: 3, update: 3]

  alias ChatWeb.ElectricLive.DialogSandboxLive.{ApiClient, Crypto, Keys}

  @doc "Expands or collapses the version list, fetching it on first expand."
  def toggle(socket, msg_id) do
    %{expanded_versions: expanded, message_versions: cached} = socket.assigns

    cond do
      msg_id in expanded ->
        assign(socket, :expanded_versions, MapSet.delete(expanded, msg_id))

      Map.has_key?(cached, msg_id) ->
        assign(socket, :expanded_versions, MapSet.put(expanded, msg_id))

      true ->
        socket
        |> assign(:expanded_versions, MapSet.put(expanded, msg_id))
        |> fetch(msg_id)
    end
  end

  @doc "Refetches versions of an expanded message, drops the cache of a collapsed one."
  def refresh_if_expanded(socket, msg_id) do
    if msg_id in socket.assigns.expanded_versions do
      fetch(socket, msg_id)
    else
      update(socket, :message_versions, &Map.delete(&1, msg_id))
    end
  end

  defp fetch(socket, msg_id) do
    base_url = public_url(socket)
    keys_cache = socket.assigns.msg_keys_cache

    case ApiClient.fetch_message_versions(msg_id, base_url, Keys.auth(socket)) do
      {:ok, %{versions: raw, log_entries: logs}} ->
        versions =
          raw
          |> Enum.sort_by(& &1["owner_timestamp"], :desc)
          |> Enum.map(&Crypto.decrypt_single_message(&1, keys_cache))

        socket
        |> update(:message_versions, &Map.put(&1, msg_id, versions))
        |> update(:request_log, &(&1 ++ logs))

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(:error_message, reason)
        |> update(:request_log, &(&1 ++ logs))
    end
  end
end
