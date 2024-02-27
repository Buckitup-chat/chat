defmodule Chat.Db.Pipeline.WriterProcess do
  @moduledoc """
  Genserver to host Writer

  """
  import Chat.Db.Pipeline.Writer
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
    |> ok_continue(:demand)
  end

  @impl true
  def handle_cast({:mirror, {_operation, _list} = payload}, state) do
    state
    |> handle_operation(payload)
    |> noreply()
  end

  def handle_cast({_operation, _list} = payload, state) do
    state
    |> handle_operation(payload)
    |> noreply_continue(:demand)
  end

  @impl true
  def handle_continue(:demand, state) do
    state
    |> demand_queue()
    |> noreply()
  rescue
    _ -> noreply(state)
  end

  @impl true
  def handle_info(:fsync, state) do
    state
    |> cancel_fsync_timer()
    |> notify_compactor()
    |> fsync()
    |> noreply()
  end

  defp handle_operation(state, {operation, list}) do
    state
    |> notify_compactor()
    |> then(fn st ->
      case operation do
        :write -> db_write(st, list)
        :delete -> db_delete(st, list)
      end
    end)
    |> start_fsync_timer()
    |> may_fsync()
  end

  defp may_fsync(state) do
    if fsync_needed?(state) do
      state |> fsync()
    else
      state
    end
  end
end
