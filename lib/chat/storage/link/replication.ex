defmodule Chat.Storage.Link.Replication do
  @moduledoc """
  Live follow of `from` by `to`, and its teardown.

  `start/1`:
  - `:cub` — mirror `from`'s CubDB writes into every unit it replicates to
  - `:pg` — publication + slot on `from`, subscription on `to` (a fresh slot each time,
    so a stale one never replays rows `bootstrap/1` already copied)
  - registers `from` as the replication source of `to`, so `ReplicationListener` on
    `to` stamps `missing_chunks.source_drive_id = from.system_id`

  `stop/1` removes the mirror, drops the subscription on `to` if it is still up, and
  always drops the slot on `from` — otherwise an ejected `to` leaves `from`
  retaining WAL.
  """

  use Toolbox.OriginLog

  alias Chat.Db.Switching
  alias Chat.Storage.Link
  alias Chat.Storage.Link.Filter
  alias Chat.Storage.Links
  alias Chat.Storage.Pg.LogicalReplicator
  alias Chat.Storage.Unit

  @spec start(Link.t()) :: :ok | {:error, term()}
  def start(%Link{} = link) do
    layers = Link.layers(link)

    case if(:pg in layers, do: start_pg(link), else: :ok) do
      :ok ->
        Links.put_status(link, :replicating)
        if :pg in layers, do: Links.register_source(link.to, link.from)
        sync_mirrors(link.from)
        log("#{inspect(Link.id(link))} replicating #{inspect(layers)}", :info)
        :ok

      {:error, reason} = error ->
        Links.put_status(link, {:error, reason})
        log("#{inspect(Link.id(link))} replicate failed #{inspect(reason)}", :error)
        error
    end
  end

  @spec stop(Link.t()) :: :ok
  def stop(%Link{from: from, to: to} = link) do
    Links.put_status(link, :stopped)
    sync_mirrors(from)

    if :pg in Link.layers(link) do
      Links.unregister_source(to, from)
      slot = Link.name(link, :slot)

      _ = safely(fn -> LogicalReplicator.drop_subscription_if_exists(Unit.repo(to), slot) end)
      _ = safely(fn -> LogicalReplicator.release_slot(Unit.repo(from), slot) end)
    end

    log("#{inspect(Link.id(link))} stopped", :info)
    :ok
  end

  @doc "Bytes `to`'s subscription lags behind `from`."
  @spec lag(Link.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def lag(%Link{to: to} = link) do
    safely(fn ->
      LogicalReplicator.check_replication_lag(Unit.repo(to), Link.name(link, :subscription))
    end)
  end

  defp start_pg(%Link{from: from, to: to, filter: filter} = link) do
    LogicalReplicator.follow(
      Unit.repo(from),
      Unit.repo(to),
      Filter.tables(filter),
      Link.name(link, :publication),
      Link.name(link, :slot)
    )
  end

  # CubDB mirrors of `from` = the units its replicating links point to
  defp sync_mirrors(%Unit{} = from) do
    from_cub = Unit.cub_name(from)

    if cub?(from) and running?(from_cub) do
      from.role
      |> running_mirror_targets()
      |> apply_mirrors(from_cub)
    end
  end

  defp running_mirror_targets(from_role) do
    from_role
    |> Links.replicating_from()
    |> Enum.map(fn {_from_role, to_role} -> Unit.cub_name(to_role) end)
    |> Enum.filter(&running?/1)
  end

  defp apply_mirrors([], from_cub), do: Switching.unmirror(from_cub)
  defp apply_mirrors(to_cubs, from_cub), do: Switching.mirror(from_cub, to_cubs)

  defp cub?(unit), do: :cub in Unit.capabilities(unit)
  defp running?(name), do: name |> Process.whereis() |> is_pid()

  # The `to` unit may be gone: its repo is stopped or never existed
  defp safely(fun) do
    fun.()
  rescue
    e -> {:error, e}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end
end
