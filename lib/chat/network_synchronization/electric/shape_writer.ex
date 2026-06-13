defmodule Chat.NetworkSynchronization.Electric.ShapeWriter do
  @moduledoc "Writes Electric shape change messages to local PostgreSQL"

  use Toolbox.OriginLog

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Shapes
  alias Chat.NetworkSynchronization.Electric.DeferredStore

  def write(shape, operation, value, opts \\ []) do
    case do_write(shape, operation, value, opts) do
      {:ok, _} = result ->
        result

      {:error, :repo_not_available} = error ->
        log("repo not available while writing #{inspect(shape)}/#{inspect(operation)}", :warning)
        error

      {:error, {:repo_not_available, reason}} = error ->
        log(
          "repo not available while writing #{inspect(shape)}/#{inspect(operation)}: #{Exception.message(reason)}",
          :warning
        )

        error

      {:error, reason} = error ->
        log(
          "failed to write #{inspect(shape)}/#{inspect(operation)}: #{inspect(reason)}",
          :warning
        )

        error
    end
  end

  defp do_write(shape_name, operation, value, opts) do
    shape_mod = Shapes.by_name(shape_name)

    case check_parents(shape_mod, operation, value) do
      :ok ->
        value
        |> shape_mod.sync_derive_fields()
        |> then(&shape_mod.sync_persist(operation, &1))
        |> tap_ok(fn result ->
          shape_mod.sync_after_persist(operation, result, opts)
          notify_deferred_children(shape_name, result)
        end)

      {:skip, missing_parents} ->
        maybe_defer(shape_name, operation, value, missing_parents, opts)
        {:ok, :skipped_no_parent}

      {:error, _} = error ->
        error
    end
  rescue
    e in RuntimeError -> {:error, {:repo_not_available, e}}
    e in Postgrex.Error -> {:error, e}
  end

  defp check_parents(shape_mod, operation, value) do
    shape_mod.sync_required_parents(operation, value)
    |> Enum.reduce_while([], fn ref, acc ->
      case check_parent(shape_mod, ref, value) do
        :ok -> {:cont, acc}
        {:skip, parent_ref} -> {:cont, [parent_ref | acc]}
        {:reject, reason} -> {:halt, {:error, {:rejected, reason}}}
      end
    end)
    |> then(fn
      {:error, _} = error -> error
      [] -> :ok
      missing -> {:skip, Enum.reverse(missing)}
    end)
  end

  defp check_parent(shape_mod, {parent_shape, parent_key} = ref, value) do
    parent_mod = Shapes.by_name(parent_shape)

    case get_parent(parent_mod.schema_module(), parent_key) do
      nil -> {:skip, ref}
      _parent -> shape_mod.sync_validate_parent(ref, value)
    end
  end

  defp get_parent(schema, key) when is_tuple(key) do
    pk_fields = schema.__schema__(:primary_key)
    pk_values = Tuple.to_list(key)
    clauses = Enum.zip(pk_fields, pk_values)
    repo().get_by(schema, clauses)
  end

  defp get_parent(schema, key), do: repo().get(schema, key)

  defp maybe_defer(shape_name, operation, value, missing_parents, opts) do
    case Keyword.fetch(opts, :peer_url) do
      {:ok, peer_url} ->
        key = Ecto.primary_key(value)
        DeferredStore.defer(shape_name, key, operation, missing_parents, peer_url)

        log(
          "Deferred #{shape_name} #{operation} - waiting on #{inspect(missing_parents)}",
          :debug
        )

      :error ->
        log_missing_parents(shape_name, operation, missing_parents)
    end
  end

  defp log_missing_parents(shape_name, operation, missing_parents) do
    parent_names = Enum.map(missing_parents, &elem(&1, 0))

    log(
      "Skipping #{shape_name} #{operation} - parents #{inspect(parent_names)} not found",
      :debug
    )
  end

  defp notify_deferred_children(shape_name, persisted_struct) do
    shape_name
    |> extract_parent_key(persisted_struct)
    |> then(&DeferredStore.check_children(shape_name, &1))
    |> case do
      [] -> :ok
      children -> DeferredStore.trigger_redeliver(children)
    end
  end

  defp extract_parent_key(shape_name, struct) do
    Shapes.by_name(shape_name).schema_module().__schema__(:primary_key)
    |> Enum.map(&Map.fetch!(struct, &1))
    |> then(fn
      [single] -> single
      multiple -> List.to_tuple(multiple)
    end)
  end

  defp tap_ok({:ok, result}, fun) do
    fun.(result)
    {:ok, result}
  end

  defp tap_ok(other, _fun), do: other
end
