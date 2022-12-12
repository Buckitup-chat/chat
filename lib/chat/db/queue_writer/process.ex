defmodule Chat.Db.QueueWriter.Process do
  @moduledoc """
  Genserver to host QueueWriter

  """
  import Chat.Db.QueueWriter
  import Tools.GenServerHelpers

  use GenServer

  #
  #   Implementation
  #

  def start_link(opts) do
    name = opts |> Keyword.fetch!(:name)

    GenServer.start_link(__MODULE__, opts |> Keyword.drop([:name]), name: name)
  end

  @impl true
  def init(opts) do
    opts
    |> from_opts()
    |> decide_if_dry()
    |> ok_continue(:demand)
  end

  @impl true
  def handle_cast({operation, list}, state) do
    state
    |> cancel_fsync_timer()
    |> cancel_compaction_timer()
    |> abort_compaction()
    |> then(fn st ->
      case operation do
        :write -> db_write(st, list)
        :delete -> db_delete(st, list)
      end
    end)
    |> start_fsync_timer()
    |> noreply_continue(:should_fsync?)
  end

  @impl true
  def handle_continue(:should_fsync?, state) do
    if fsync_needed?(state) do
      state
      |> fsync()
      |> noreply_continue(:demand)
    else
      noreply_continue(state, :demand)
    end
  end

  def handle_continue(:demand, state) do
    state
    |> demand_queue()
    |> noreply()
  end

  @impl true
  def handle_info(:compact, state) do
    state
    |> start_compaction()
    |> noreply()
  end

  def handle_info(:fsync, state) do
    state
    |> cancel_fsync_timer()
    |> abort_compaction()
    |> cancel_compaction_timer()
    |> fsync()
    |> noreply()
  end
end
