defmodule Chat.NetworkSynchronization.Electric.ShapeWriter do
  @moduledoc "Writes Electric shape change messages to local PostgreSQL"

  use Toolbox.OriginLog

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Shapes

  def write(shape, operation, value) do
    case do_write(shape, operation, value) do
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

  defp do_write(shape_name, operation, value) do
    shape_mod = Shapes.by_name(shape_name)

    with :ok <- check_parents(shape_mod, operation, value) do
      value
      |> shape_mod.sync_derive_fields()
      |> then(&shape_mod.sync_persist(operation, &1))
    end
  rescue
    e in RuntimeError -> {:error, {:repo_not_available, e}}
    e in Postgrex.Error -> {:error, e}
  end

  defp check_parents(shape_mod, operation, value) do
    shape_mod.sync_required_parents(operation, value)
    |> Enum.reduce_while(:ok, fn ref, :ok ->
      case check_parent(shape_mod, ref, value) do
        :ok ->
          {:cont, :ok}

        {:skip, parent_shape} ->
          log(
            "Skipping #{shape_mod.shape_name()} #{operation} - parent #{parent_shape} not found",
            :debug
          )

          {:halt, {:ok, :skipped_no_parent}}

        {:reject, reason} ->
          {:halt, {:error, {:rejected, reason}}}
      end
    end)
  end

  defp check_parent(shape_mod, {parent_shape, parent_key} = ref, value) do
    parent_mod = Shapes.by_name(parent_shape)

    case repo().get(parent_mod.schema_module(), parent_key) do
      nil -> {:skip, parent_shape}
      _parent -> shape_mod.sync_validate_parent(ref, value)
    end
  end
end
