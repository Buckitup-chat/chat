defmodule Chat.NetworkSynchronization do
  @moduledoc "Network synchronisation"

  alias Chat.NetworkSynchronization.Store
  alias Chat.NetworkSynchronization.Source
  alias Chat.NetworkSynchronization.Worker

  alias Phoenix.PubSub

  @registry Chat.NetworkSynchronization.Supervisor.Registry
  @dynamic_supervisor Chat.NetworkSynchronization.Supervisor.Dynamic

  def synchronisation, do: Store.list_sources_with_status()

  def add_source, do: Store.add_source()
  def remove_source(id), do: id |> cast_source() |> Store.delete_source()

  def update_source(id, fields) do
    cast_source(id)
    |> merge_sanitised_fields(fields)
    |> Store.update_source()
  end

  def update_status(source, status) do
    id = source |> get_id()

    Store.update_source_status(id, status)
    broadcast_status_update(id, status)
  end

  def notification_topic, do: "chat::NetworkSynchronization"

  def monotonic_ms, do: System.monotonic_time(:millisecond)

  def init_workers do
    synchronisation()
    |> started_workers_for_started_sources()
  end

  def start_source(id) do
    find_source_by_id(id)
    |> tap(&start_worker/1)
    |> struct(started?: true)
    |> Store.update_source()
  end

  def stop_source(id) do
    stop_worker(id)

    find_source_by_id(id)
    |> struct(started?: false)
    |> Store.update_source()
    |> update_status(nil)
  end

  defp cast_source(id), do: Source.new(id)

  defp merge_sanitised_fields(source, fields) do
    fields
    |> Keyword.take([:url, :cooldown_hours])
    |> Enum.map(fn
      {:url, string} when is_binary(string) ->
        if String.valid?(string), do: {:url, string}, else: nil

      {:cooldown_hours, string} ->
        case Integer.parse(string) do
          {int, ""} -> {:cooldown_hours, max(1, int)}
          _ -> nil
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> then(&struct(source, &1))
  end

  defp find_source_by_id(id) do
    {source, _} =
      synchronisation()
      |> Enum.find(&match?({%{id: ^id}, _}, &1))

    source
  end

  defp get_id(source) do
    if is_integer(source),
      do: source,
      else: source.id
  end

  defp broadcast_status_update(id, status) do
    :ok =
      PubSub.broadcast!(
        Chat.PubSub,
        notification_topic(),
        {:admin, {:network_source_status, id, status}}
      )
  end

  defp started_workers_for_started_sources(list) do
    list
    |> Enum.filter(&match?({%{started?: true}, nil}, &1))
    |> Enum.each(fn {source, _} -> start_worker(source, true) end)
  end

  # Supervision

  defp start_worker(source, deferred? \\ false) do
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        @dynamic_supervisor,
        {Worker, name: via_name(source.id), source: source, deferred: deferred?}
      )
  end

  defp stop_worker(id) do
    [{pid, _}] = Registry.lookup(@registry, id)
    DynamicSupervisor.terminate_child(@dynamic_supervisor, pid)
  end

  defp via_name(id) do
    {:via, Registry, {@registry, id}}
  end
end
