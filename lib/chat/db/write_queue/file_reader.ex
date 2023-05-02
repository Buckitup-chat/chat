defmodule Chat.Db.WriteQueue.FileReader do
  @moduledoc """
  File reading for ReadStream
  """
  require Logger

  def add_task(readers, {:file_chunk, chunk_key, first, _} = key, files_path) do
    task =
      Task.async(fn ->
        {key, Chat.FileFs.read_file_chunk(first, chunk_key, files_path) |> elem(0)}
      end)

    List.insert_at(readers, -1, task)
    |> tap(fn readers ->
      readers
      |> inspect(pretty: true)
      |> Logger.debug()
    end)
  end

  def yield_file(readers), do: find_first_ready(readers, [])

  defp find_first_ready([], acc), do: {nil, acc |> Enum.reverse()}

  defp find_first_ready([task | rest], acc) do
    case check_task(task) do
      {:ok, data} -> {data, Enum.reverse(acc) ++ rest}
      nil -> find_first_ready(rest, [task | acc])
    end
  end

  defp check_task(%Task{} = task), do: Task.yield(task, 7)
  defp check_task([x]), do: x

  defp check_task(any) do
    any
    |> inspect(pretty: true)
    |> Logger.error()

    nil
  end
end
