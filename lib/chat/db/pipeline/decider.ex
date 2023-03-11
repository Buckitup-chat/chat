defmodule Chat.Db.Pipeline.Decider do
  @moduledoc """
  Checks free space and devices writing mode
  Starts different set of processes
  """
  use GenServer

  import Tools.GenServerHelpers

  alias Chat.Db.Pipeline.Compactor
  alias Chat.Db.Pipeline.DryWriter
  alias Chat.Db.Pipeline.WriterProcess

  alias Chat.Db.Maintenance

  @dry_threshold_b 100 * 1024 * 1024

  def start_link(opts) do
    name = opts |> Keyword.fetch!(:name)

    GenServer.start_link(__MODULE__, opts |> Keyword.drop([:name]), name: name)
  end

  @impl true
  def init(opts) do
    db = Keyword.fetch!(opts, :db)
    relay = Keyword.fetch!(opts, :status_relay)

    if has_no_free_space(db) do
      set_dry(relay, true)
      start_dry_writer(opts)
    else
      set_dry(relay, false)
      start_writer(opts)
    end
    |> ok()
  end

  defp has_no_free_space(db), do: Maintenance.db_free_space(db) < @dry_threshold_b

  defp set_dry(relay, value) do
    Agent.update(relay, fn _ -> value end)
  end

  defp start_writer(opts) do
    dyn_supervisor = Keyword.fetch!(opts, :write_supervisor)
    compactor = Keyword.fetch!(opts, :compactor)
    db = Keyword.fetch!(opts, :db)
    writer = Keyword.fetch!(opts, :writer)

    [
      {Compactor, name: compactor, db: db},
      {WriterProcess, [name: writer] ++ Keyword.drop(opts, [:writer])}
    ]
    |> Enum.each(fn child ->
      DynamicSupervisor.start_child(dyn_supervisor, child)
    end)
  end

  defp start_dry_writer(opts) do
    dyn_supervisor = Keyword.fetch!(opts, :dynamic_supervisor)
    writer = Keyword.fetch!(opts, :writer)

    DynamicSupervisor.start_child(
      dyn_supervisor,
      {DryWriter, [name: writer] ++ Keyword.drop(opts, [:writer])}
    )
  end
end
