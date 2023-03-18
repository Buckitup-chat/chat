defmodule Chat.Db.Pipeline.DryWriter do
  @moduledoc """
  Mimics Wrtiter but does nothing
  """
  import Tools.GenServerHelpers

  alias Chat.Db.ChangeTracker
  alias Chat.Db.WriteQueue, as: Queue

  use GenServer

  def write(proc, list), do: GenServer.cast(proc, {:write, list})
  def delete(proc, list), do: GenServer.cast(proc, {:delete, list})

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
    |> Keyword.fetch!(:queue)
    |> ok_continue(:demand)
  end

  @impl true
  def handle_cast({operation, list}, state) do
    case operation do
      :write ->
        list
        |> Enum.map(&elem(&1, 0))
        |> ChangeTracker.set_written()

      :delete ->
        :noop
    end

    state |> noreply_continue(:demand)
  end

  @impl true
  def handle_continue(:demand, queue = state) do
    Queue.demand(queue)
    state |> noreply()
  end
end
