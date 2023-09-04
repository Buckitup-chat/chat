defmodule Chat.Db.WriteQueue.FileReader do
  @moduledoc """
  File reading for ReadStream
  """
  require Logger
  import Tools.GenServerHelpers

  use GenServer

  defstruct name: nil, read_supervisor: nil, harvest: %{}, keys: %{}

  def add_task(server, {:file_chunk, _, _, _} = key, files_path) do
    server
    |> GenServer.call({:add_task, key, files_path})
  end

  def yield_file(server, readers) do
    refs =
      readers
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.get(&1, :ref))

    server
    |> GenServer.call({:yield, refs})
    |> first_file_and_updated_readers(readers)
  end

  defp first_file_and_updated_readers(harvest, readers) do
    {files, tasks} = Enum.split_with(readers, &match?({{:file_chunk, _, _, _}, _}, &1))

    {more_files, still_tasks} =
      Enum.split_with(tasks, fn %{ref: ref} ->
        Map.has_key?(harvest, ref)
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
    __MODULE__
    |> struct(opts)
    |> ok()
  end

  @impl true
  def handle_call(
        {:add_task, key, files_path},
        _,
        %__MODULE__{read_supervisor: task_supervisor, keys: keys} = state
      ) do
    task =
      %{ref: ref} =
      Task.Supervisor.async(task_supervisor, fn ->
        read_or_fail_with(key, files_path, :retry)
        |> case do
          :retry -> read_or_fail_with(key, files_path, :error)
          good -> good
        end
      end)

    state
    |> Map.put(:keys, Map.put(keys, ref, key))
    |> reply(task)
  end

  def handle_call({:yield, refs}, _from, %{harvest: harvest} = state) do
    %{state | harvest: Map.drop(harvest, refs)}
    |> reply(harvest |> Map.take(refs))
  end

  @impl true
  def handle_info({ref, data}, %__MODULE__{harvest: prev, keys: keys, name: name} = state) do
    Process.demonitor(ref, [:flush])

    case data do
      :error ->
        log_error_reading(keys[ref], name)
        state

      {_key, _content} = data ->
        state
        |> Map.put(:harvest, Map.put(prev, ref, data))
    end
    |> Map.put(:keys, Map.delete(keys, ref))
    |> noreply()
  end

  def handle_info({:DOWN, ref, :process, _, reason}, %__MODULE__{keys: keys, name: name} = state) do
    log_reader_ended(keys[ref], reason, name)

    state
    |> Map.put(:keys, Map.delete(keys, ref))
    |> noreply()
  end

  def handle_info({:DOWN, _, _, _, _} = msg, %__MODULE__{name: name} = state) do
    log_unhandled_msg(msg, name)
    state |> noreply()
  end

  defp read_or_fail_with({:file_chunk, chunk_key, first, last} = key, path, fail_marker) do
    try do
      Chat.FileFs.read_exact_file_chunk({first, last}, chunk_key, path)
      |> case do
        {"", _} -> fail_marker
        {content, _} -> {key, content}
      end
    rescue
      _ -> fail_marker
    end
  end

  defp log_reader_ended(key, reason, name) do
    "#{name} Reading #{key} ended with reason: #{reason}" |> log(:error)
  end

  defp log_unhandled_msg(msg, name) do
    ["#{name} Unhandled message ", inspect(msg)] |> log(:debug)
  end

  defp log_error_reading(msg, name) do
    "#{name} Error reading #{inspect(msg)}" |> log(:warn)
  end

  defp log(message, level) do
    [
      "[copying] ",
      "[file reader] ",
      message
    ]
    |> then(&Logger.log(level, &1))
  end
end
