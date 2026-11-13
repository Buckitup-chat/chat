defmodule Chat.Storage.Default do
  @moduledoc """
  The Default unit: the one storage unit the CubDB write queue, the PG repo, the
  upload chunk writer and Electric point at.

  It is a single `:persistent_term` value, so the repo and the upload writer
  (both derived from `unit/0`) always point at the same unit. `switch_to/1` is the
  only setter. Only edges read it (controllers, shapes, `Chat.Db.repo/0`,
  FileFs readers); everything below them takes a `%Unit{}`.

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.6.
  """

  use Toolbox.OriginLog

  alias Chat.Db.Switching
  alias Chat.Storage.Default.Electric
  alias Chat.Storage.Unit
  alias Chat.Sync.DbBrokers

  # Literal module: Rewire copies this module under another name in tests
  @key {Chat.Storage.Default, :unit}
  @topic "storage"

  @doc "The Default unit; internal until the first `switch_to/1`."
  @spec unit() :: Unit.t()
  def unit, do: :persistent_term.get(@key, nil) || Unit.internal()

  @doc """
  Makes `unit` the Default, in the steps of spec §2.6:

  1. stop the Electric stack
  2. release Electric's PG state and cache on the old unit (skipped if it is gone)
  3. CubDB write queue · 4. PG repo · 5. upload writer := `unit`
  6. ensure the Electric slot on `unit` and start the stack on it
  7. `DbBrokers.refresh/0` · 8. broadcast `{:default_switched, unit}` on `"storage"`
  """
  @spec switch_to(Unit.t()) :: :ok | {:error, term()}
  def switch_to(%Unit{} = new) do
    old = unit()
    log("switching #{inspect(old.id)} -> #{inspect(new.id)}", :info)

    Electric.stop()
    if same?(old, new), do: :ok, else: Electric.release(old)

    new |> Unit.cub_name() |> Switching.set_default()
    :persistent_term.put(@key, new)

    new
    |> Electric.start()
    |> tap(fn _ -> DbBrokers.refresh() end)
    |> tap(fn _ -> Phoenix.PubSub.broadcast(Chat.PubSub, @topic, {:default_switched, new}) end)
  end

  defp same?(%Unit{id: id, role: role}, %Unit{id: id, role: role}), do: true
  defp same?(_old, _new), do: false
end
