defmodule Chat.Db.FileFsProxy do
  @moduledoc "Write files in only thread (no concurency)"

  # todo: remove

  use GenServer

  alias Chat.FileFs

  def write_file(data, {_, _, _} = keys, prefix \\ nil) do
    __MODULE__
    |> GenServer.call({:write, {data, keys, prefix}}, :timer.minutes(5))
  end

  def delete_file(key, prefix \\ nil) do
    __MODULE__
    |> GenServer.cast({:delete, {key, prefix}})
  end

  #
  # GenServer implementation
  #

  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, true}
  end

  @impl true
  def handle_call({:write, {data, keys, prefix}}, _, state) do
    FileFs.write_file(data, keys, prefix)
    |> then(&{:reply, &1, state})
  end

  @impl true
  def handle_cast({:delete, {key, prefix}}, state) do
    FileFs.delete_file(key, prefix)
    {:noreply, state}
  end
end
