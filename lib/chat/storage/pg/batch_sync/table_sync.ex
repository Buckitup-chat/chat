defmodule Chat.Storage.Pg.BatchSync.TableSync do
  @moduledoc """
  Table-level synchronization operations.
  Handles diffing, batch copying, query building, and conflict resolution
  for individual Ecto schema tables.
  """

  use Toolbox.OriginLog

  import Ecto.Query

  @doc """
  Syncs a single table. Returns one of:

  - `{:ok, count}` — all missing rows were copied
  - `{:partial, count, reason}` — some rows were skipped because Postgres rejected
    them (constraint/data error); `count` is the number actually copied. The caller
    should keep syncing other tables.
  - `{:abort, reason}` — the sync cannot make progress (connection lost, repo
    unavailable, …); the caller should stop.
  """
  def sync_table(source_repo, target_repo, schema_module, batch_size, config) do
    id_field = config.id_field

    source_ids =
      source_repo.all(build_select_query(schema_module, id_field))
      |> MapSet.new()

    target_ids =
      target_repo.all(build_select_query(schema_module, id_field))
      |> MapSet.new()

    missing_ids = MapSet.difference(source_ids, target_ids)
    missing_count = MapSet.size(missing_ids)

    if missing_count == 0 do
      log("no missing rows for #{inspect(schema_module)}", :debug)
      {:ok, 0}
    else
      log(
        "syncing #{missing_count} missing rows for #{inspect(schema_module)}",
        :info
      )

      copy_missing_batches(
        source_repo,
        target_repo,
        schema_module,
        missing_ids,
        batch_size,
        config
      )
    end
  rescue
    e in Postgrex.Error ->
      log(
        "exception during sync schema=#{inspect(schema_module)} error=#{inspect(e)}",
        :error
      )

      if match?(%Postgrex.Error{postgres: %{}}, e) do
        {:partial, 0, e}
      else
        {:abort, e}
      end

    e ->
      log(
        "connection error during sync schema=#{inspect(schema_module)} error=#{inspect(e)}",
        :error
      )

      {:abort, e}
  end

  # Copy missing rows batch by batch. A batch that Postgres rejects is skipped and we
  # continue with the remaining batches; a connection-level failure halts the table.
  defp copy_missing_batches(
         source_repo,
         target_repo,
         schema_module,
         missing_ids,
         batch_size,
         config
       ) do
    missing_ids
    |> MapSet.to_list()
    |> Stream.chunk_every(batch_size)
    |> Enum.reduce_while({:copied, 0, nil}, fn batch_ids, {:copied, total, first_error} ->
      case sync_batch(source_repo, target_repo, schema_module, batch_ids, config) do
        {:ok, count} ->
          {:cont, {:copied, total + count, first_error}}

        {:error, %Postgrex.Error{postgres: %{}} = reason} ->
          log(
            "skipping batch schema=#{inspect(schema_module)} reason=#{inspect(reason)}",
            :error
          )

          {:cont, {:copied, total, first_error || reason}}

        {:error, reason} ->
          {:halt, {:abort, reason}}
      end
    end)
    |> case do
      {:abort, reason} -> {:abort, reason}
      {:copied, total, nil} -> {:ok, total}
      {:copied, total, reason} -> {:partial, total, reason}
    end
  end

  # Sync a batch of rows
  defp sync_batch(source_repo, target_repo, schema_module, batch_ids, config) do
    id_field = config.id_field

    rows =
      source_repo.all(build_where_query(schema_module, id_field, batch_ids))

    db_fields = schema_module.__schema__(:fields)

    entries =
      Enum.map(rows, fn row ->
        row
        |> Map.from_struct()
        |> Map.take(db_fields)
        |> maybe_add_timestamps(schema_module)
      end)

    case insert_all_safe(target_repo, schema_module, entries, config) do
      {:ok, count} ->
        {:ok, count}

      {:error, reason} ->
        log(
          "batch insert failed reason=#{inspect(reason)}",
          :error
        )

        {:error, reason}
    end
  end

  # Safe wrapper for insert_all that handles conflicts
  defp insert_all_safe(_repo, _schema_module, entries, _config) when entries == [] do
    {:ok, 0}
  end

  defp insert_all_safe(repo, schema_module, entries, config) do
    opts = build_insert_opts(config)

    {count, _} = repo.insert_all(schema_module, entries, opts)

    {:ok, count}
  rescue
    e in Postgrex.Error ->
      {:error, e}

    e ->
      {:error, e}
  end

  defp build_insert_opts(config) do
    base_opts = [conflict_target: config.conflict_target]

    case config.on_conflict do
      :nothing ->
        Keyword.put(base_opts, :on_conflict, :nothing)

      :replace_all ->
        Keyword.put(base_opts, :on_conflict, :replace_all)

      {:update, fields} when is_list(fields) ->
        Keyword.put(base_opts, :on_conflict, {:replace, fields})

      _ ->
        Keyword.put(base_opts, :on_conflict, :nothing)
    end
  end

  # Timestamps

  defp maybe_add_timestamps(attrs, schema_module) do
    now = Chat.TimeKeeper.now() |> DateTime.truncate(:second)

    attrs
    |> maybe_put_timestamp(:inserted_at, now, schema_module)
    |> maybe_put_timestamp(:updated_at, now, schema_module)
  end

  defp maybe_put_timestamp(attrs, field, value, schema_module) do
    if has_field?(schema_module, field) and is_nil(Map.get(attrs, field)) do
      Map.put(attrs, field, value)
    else
      attrs
    end
  end

  defp has_field?(schema_module, field) do
    field in schema_module.__schema__(:fields)
  end

  # Query builders

  defp build_select_query(schema_module, id_field) when is_atom(id_field) do
    from(s in schema_module, select: field(s, ^id_field))
  end

  defp build_select_query(schema_module, id_fields) when is_list(id_fields) do
    case id_fields do
      [field1, field2] ->
        from(s in schema_module, select: {field(s, ^field1), field(s, ^field2)})

      [field1, field2, field3] ->
        from(s in schema_module,
          select: {field(s, ^field1), field(s, ^field2), field(s, ^field3)}
        )

      _ ->
        raise "Composite keys with #{length(id_fields)} fields not yet supported"
    end
  end

  defp build_where_query(schema_module, id_field, batch_ids) when is_atom(id_field) do
    from(s in schema_module,
      where: field(s, ^id_field) in ^batch_ids
    )
  end

  defp build_where_query(schema_module, id_fields, batch_ids) when is_list(id_fields) do
    Enum.reduce(batch_ids, from(s in schema_module, where: false), fn id_tuple, query ->
      conditions =
        id_fields
        |> Enum.zip(Tuple.to_list(id_tuple))
        |> Enum.map(fn {field, value} ->
          dynamic([s], field(s, ^field) == ^value)
        end)
        |> Enum.reduce(&dynamic([s], ^&1 and ^&2))

      from(s in query, or_where: ^conditions)
    end)
  end
end
