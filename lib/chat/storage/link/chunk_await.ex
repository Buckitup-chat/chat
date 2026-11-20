defmodule Chat.Storage.Link.ChunkAwait do
  @moduledoc """
  Waits until every link's `to` holds the blobs its `from` provided: no
  `missing_chunks` row on `to` with `source_drive_id = from.system_id`.

  Gives up after `:stall_ms` without progress, like `Backup.ChunkAwaiter` did.
  Progress goes to `Chat.Storage.Links` as `{:awaiting, {done, total}}`.
  """

  use Toolbox.OriginLog

  import Ecto.Query

  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Storage.Link
  alias Chat.Storage.Links
  alias Chat.Storage.Unit

  @poll_ms 1_000
  @stall_ms 60_000

  @spec run([Link.t()], keyword()) :: :ok | {:stalled, %{Link.id() => pos_integer()}}
  def run(links, opts) do
    poll_ms = Keyword.get(opts, :poll_ms, @poll_ms)
    stall_ms = Keyword.get(opts, :stall_ms, @stall_ms)
    links = Enum.filter(links, &(:blobs in Link.layers(&1)))
    totals = Map.new(links, &{Link.id(&1), remaining(&1)})

    poll(links, totals, totals, %{poll_ms: poll_ms, stall_ms: stall_ms, stalled_ms: 0})
  end

  defp poll(links, totals, previous, ctx) do
    current = Map.new(links, &{Link.id(&1), remaining(&1)})
    Enum.each(links, &report(&1, totals, current))

    cond do
      Enum.all?(current, fn {_id, left} -> left == 0 end) ->
        Enum.each(links, &Links.put_status(&1, :idle))
        :ok

      ctx.stalled_ms >= ctx.stall_ms ->
        stalled = current |> Enum.reject(fn {_id, left} -> left == 0 end) |> Map.new()
        log("chunk await stalled #{inspect(stalled)}", :warning)
        {:stalled, stalled}

      true ->
        Process.sleep(ctx.poll_ms)
        stalled_ms = if current == previous, do: ctx.stalled_ms + ctx.poll_ms, else: 0
        poll(links, totals, current, %{ctx | stalled_ms: stalled_ms})
    end
  end

  defp report(link, totals, current) do
    id = Link.id(link)
    total = max(totals[id], current[id])
    Links.put_status(link, {:awaiting, {total - current[id], total}})
  end

  defp remaining(%Link{from: %Unit{system_id: source}, to: to}) do
    repo = Unit.repo(to)

    from(m in MissingChunk, where: m.source_drive_id == ^source, select: count())
    |> repo.one()
  end
end
