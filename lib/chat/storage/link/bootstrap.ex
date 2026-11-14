defmodule Chat.Storage.Link.Bootstrap do
  @moduledoc """
  One-shot catch-up of `to` from `from`, layer by layer:

  1. `:cub` — `Chat.Db.Copying.await_copied/3`, scoped by the filter's `cub_scope`
  2. `:rows` — `Chat.Storage.Pg.BatchSync` diff+copy of the filter's schemas
  3. `:chunks` — `missing_chunks` on `to` for every `file_chunks` row whose blob `to`
     lacks, with `source_drive_id = from.system_id` (spec §5 invariant 6); new rows
     nudge the chunk pipelines (`{:chunk_pipeline, :pg_diff_copied}`) so `to` pulls
     the blobs right away

  A failing layer stops the ones after it. Progress and the final status go to
  `Chat.Storage.Links`; a full disk on `to` surfaces as `{:error, :disk_full}`.
  """

  use Toolbox.OriginLog

  import Ecto.Query

  alias Chat.Data.File.ChunkStore
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Db.Copying
  alias Chat.Storage.Link
  alias Chat.Storage.Link.Filter
  alias Chat.Storage.Links
  alias Chat.Storage.Pg.BatchSync
  alias Chat.Storage.Unit
  alias Chat.TimeKeeper

  @batch_size 200

  @type result :: :ok | {:partial, map()} | {:error, term()}

  @spec run(Link.t()) :: result()
  def run(%Link{} = link) do
    layers = Link.layers(link)
    Links.put_status(link, {:bootstrapping, %{}})

    [cub: :cub, rows: :pg, chunks: :blobs]
    |> Enum.filter(fn {_step, layer} -> layer in layers end)
    |> Enum.reduce_while({%{}, %{}}, fn {step, _layer}, {progress, failures} ->
      case run_step(step, link) do
        {:error, reason} -> {:halt, {:error, reason}}
        {:partial, failed} -> {:cont, advance(link, step, progress, Map.merge(failures, failed))}
        :done -> {:cont, advance(link, step, progress, failures)}
      end
    end)
    |> finish(link)
  end

  @doc "Whether a failure (any nesting) is PostgreSQL's or the filesystem's \"disk full\"."
  @spec disk_full?(term()) :: boolean()
  def disk_full?(reason) do
    case reason do
      %Postgrex.Error{postgres: %{code: :disk_full}} -> true
      :enospc -> true
      %File.Error{reason: :enospc} -> true
      %{} = map when not is_struct(map) -> map |> Map.values() |> Enum.any?(&disk_full?/1)
      list when is_list(list) -> Enum.any?(list, &disk_full?/1)
      tuple when is_tuple(tuple) -> tuple |> Tuple.to_list() |> Enum.any?(&disk_full?/1)
      _ -> false
    end
  end

  defp run_step(:cub, %Link{from: from, to: to, filter: filter} = link) do
    keys = Filter.cub_keys(filter, link)

    case Copying.await_copied(Unit.cub_name(from), Unit.cub_name(to), keys) do
      result when result in [:ok, :ignored] -> :done
    end
  end

  defp run_step(:rows, %Link{from: from, to: to, filter: filter}) do
    [source_repo: Unit.repo(from), target_repo: Unit.repo(to), schemas: Filter.schemas(filter)]
    |> BatchSync.sync()
    |> case do
      {:ok, _stats} -> :done
      {:partial, _stats, failures} -> {:partial, failures}
      {:error, _reason} = error -> error
    end
  end

  defp run_step(:chunks, %Link{} = link) do
    link
    |> backfill_chunks()
    |> tap(&log("#{inspect(Link.id(link))} backfilled #{&1} missing_chunks", :info))
    |> tap(&if(&1 > 0, do: nudge_pipelines()))
    |> then(fn _count -> :done end)
  rescue
    e in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, e}
  end

  defp backfill_chunks(%Link{from: from, to: to}) do
    repo = Unit.repo(to)
    now = TimeKeeper.now_unix()

    from(fc in FileChunk,
      where: not is_nil(fc.data_hash),
      select: %{
        file_id: fc.file_id,
        chunk_index: fc.chunk_index,
        data_hash: fc.data_hash,
        size: fc.size
      }
    )
    |> repo.all()
    |> Enum.reject(&ChunkStore.exists?(to, &1.file_id, &1.chunk_index))
    |> Enum.chunk_every(@batch_size)
    |> Enum.sum_by(fn batch ->
      rows = Enum.map(batch, &missing_row(&1, from.system_id, now))

      repo.insert_all(MissingChunk, rows,
        on_conflict: {:replace, [:source_drive_id]},
        conflict_target: [:file_id, :chunk_index]
      )
      |> elem(0)
    end)
  end

  # `to`'s drive copy source polls hourly; make it pick up the new rows now
  defp nudge_pipelines,
    do:
      Phoenix.PubSub.broadcast(Chat.PubSub, "chunk_pipeline", {:chunk_pipeline, :pg_diff_copied})

  defp missing_row(chunk, source_drive_id, now) do
    chunk
    |> Map.merge(%{peer_url: nil, source_drive_id: source_drive_id, attempts: 0, updated_at: now})
  end

  defp advance(link, step, progress, failures) do
    progress = Map.put(progress, step, :done)
    Links.put_status(link, {:bootstrapping, progress})
    {progress, failures}
  end

  defp finish(outcome, link) do
    {status, result} =
      case outcome do
        {:error, reason} ->
          reason = if disk_full?(reason), do: :disk_full, else: reason
          {{:error, reason}, {:error, reason}}

        {_progress, failures} when map_size(failures) == 0 ->
          {:idle, :ok}

        {_progress, failures} ->
          if disk_full?(failures),
            do: {{:error, :disk_full}, {:error, :disk_full}},
            else: {{:partial, failures}, {:partial, failures}}
      end

    Links.put_status(link, status)
    log("#{inspect(Link.id(link))} bootstrap #{inspect(result)}", log_level(result))
    result
  end

  defp log_level(:ok), do: :info
  defp log_level(_result), do: :warning
end
