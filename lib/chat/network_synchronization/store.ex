defmodule Chat.NetworkSynchronization.Store do
  @moduledoc "Stores sources and statuses for network synchronization"

  alias Chat.NetworkSynchronization.Source

  @source_db_prefix :network_source
  @source_table :buckitup_network_sources
  @status_table :buckitup_network_source_statuses

  def list_sources_with_status do
    statuses = list(@status_table) |> Map.new()

    list(@source_table)
    |> Enum.map(fn {_, source} ->
      {source, Map.get(statuses, source.id)}
    end)
  end

  def add_source do
    ets_size(@source_table)
    |> case do
      # coveralls-ignore-next-line
      :undefined -> 1
      n -> n + 1
    end
    |> Source.new()
    |> update_source()
  end

  def update_source(source) do
    put(@source_table, source.id, source)
    db_put(@source_db_prefix, source.id, source)

    source
  end

  def delete_source(source) do
    delete(@source_table, source.id)
    db_delete(@source_db_prefix, source.id)
  end

  def update_source_status(id, status) do
    put(@status_table, id, status)
  end

  def delete_source_status(id) do
    delete(@status_table, id)
  end

  def init do
    if ets_size(@status_table) == :undefined do
      create_table(@status_table)
    end

    if ets_size(@source_table) == :undefined do
      create_table(@source_table)

      load_from_db(@source_db_prefix)
      |> Enum.each(fn {{_, id}, value} ->
        put(@source_table, id, value)
      end)
    end
  end

  # CubDB backend

  defp load_from_db(prefix) do
    Chat.AdminDb.list({{prefix, 0}, {prefix, nil}})
  end

  defp db_put(prefix, id, source) do
    Chat.AdminDb.put({prefix, id}, source)
  end

  defp db_delete(prefix, id) do
    Chat.AdminDb.db()
    |> CubDB.delete({prefix, id})
  end

  # ETS backend

  defp list(table) do
    :ets.tab2list(table)
  rescue
    # coveralls-ignore-next-line
    _ -> []
  end

  defp ets_size(table) do
    :ets.info(table, :size)
  end

  defp delete(table, id) do
    :ets.delete(table, id)
  rescue
    # coveralls-ignore-next-line
    _ -> :ignored
  end

  defp put(table, id, item) do
    :ets.insert(table, {id, item})
  end

  defp create_table(name) do
    :ets.new(name, [:ordered_set, :named_table, :public, write_concurrency: :auto])
  end
end
