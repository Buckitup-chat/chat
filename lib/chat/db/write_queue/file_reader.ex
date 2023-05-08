defmodule Chat.Db.WriteQueue.FileReader do
  @moduledoc """
  File reading for ReadStream
  """
  require Logger
  import Tools.GenServerHelpers

  use GenServer

  def add_task(server, {:file_chunk, _, _, _} = key, files_path) do
    server
    |> GenServer.call({:add_task, key, files_path})
  end

  def yield_file(server, readers) do
    server
    |> GenServer.call(:yield)
    |> first_file_and_updated_readers(readers)
  end

  defp first_file_and_updated_readers(harvest, readers) do
    {files, tasks} = Enum.split_with(readers, &match?({{:file_chunk, _, _, _}, _}, &1))

    {more_files, still_tasks} =
      Enum.split_with(tasks, fn
        %{ref: ref} ->
          Map.has_key?(harvest, ref)

        x ->
          inspect(x) |> Logger.warn()
          x
      end)

    harvested_files =
      more_files
      |> Enum.map(fn %{ref: ref} -> Map.get(harvest, ref) end)

    new_files = files ++ harvested_files

    case new_files do
      [] -> {nil, still_tasks}
      [file | rest] -> {file, rest ++ still_tasks}
    end
  end

  # GenServer Implementation

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    opts
    |> Map.new()
    |> Map.put(:harvest, %{})
    |> ok()
  end

  @impl true
  def handle_call(
        {:add_task, {:file_chunk, chunk_key, first, _} = key, files_path},
        _,
        %{read_supervisor: task_supervisor} = state
      ) do
    state
    |> reply(
      Task.Supervisor.async(task_supervisor, fn ->
        {key, Chat.FileFs.read_file_chunk(first, chunk_key, files_path) |> elem(0)}
      end)
    )
  end

  def handle_call(:yield, _from, %{harvest: harvest} = state) do
    %{state | harvest: %{}}
    |> reply(harvest)
  end

  @impl true
  def handle_info({ref, data}, %{harvest: prev} = state) do
    state
    |> Map.put(:harvest, Map.put(prev, ref, data))
    |> noreply()
  end

  def handle_info({:DOWN, _, _, _, _}, state) do
    state |> noreply()
  end
end
