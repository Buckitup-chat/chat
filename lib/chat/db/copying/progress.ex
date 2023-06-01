defmodule Chat.Db.Copying.Progress do
  @moduledoc """
  Copy process progress state
  """

  defstruct file_keys: [],
            data_keys: [],
            db: nil,
            initial_data_count: -1,
            initial_file_count: -1,
            data_count: -1,
            file_count: -1,
            complete?: false

  @file_weight 9

  @spec new(list(), CubDB.t()) :: %__MODULE__{}
  def new(keys, db) do
    {file_keys, data_keys} = Enum.split_with(keys, &match?({:file_chunk, _, _, _}, &1))

    file_count = Enum.count(file_keys)
    data_count = Enum.count(data_keys)

    %__MODULE__{
      file_keys: file_keys,
      data_keys: data_keys,
      db: db,
      initial_data_count: data_count,
      initial_file_count: file_count,
      data_count: data_count,
      file_count: file_count,
      complete?: data_count + file_count == 0
    }
  end

  @spec eliminate_written(%__MODULE__{}) :: %__MODULE__{}
  def eliminate_written(state) do
    state
    |> eliminate_written_data()
    |> eliminate_written_files()
    |> update_counts()
    |> update_compete()
  end

  @spec recheck_delay_in_ms(%__MODULE__{}) :: non_neg_integer()
  def recheck_delay_in_ms(%__MODULE__{data_count: data_count, file_count: file_count}) do
    weight = data_count + file_count * @file_weight

    cond do
      weight < 100 -> 100
      weight < 1_000 -> 500
      weight < 10_000 -> 1_000
      weight < 100_000 -> 5_000
      true -> 29_000
    end
  end

  @spec done_percent(%__MODULE__{}) :: non_neg_integer()
  def done_percent(%__MODULE__{
        initial_data_count: initial_data_count,
        initial_file_count: initial_file_count,
        data_count: data_count,
        file_count: file_count
      }) do
    total = initial_data_count + @file_weight * initial_file_count
    left = data_count + @file_weight * file_count

    (100 - left * 100 / total)
    |> trunc()
  end

  @spec left_keys(%__MODULE__{}) :: non_neg_integer()
  def left_keys(%__MODULE__{data_count: data_count, file_count: file_count}) do
    data_count + file_count
  end

  def complete?(%__MODULE__{complete?: complete}) do
    complete
  end

  @spec get_unwritten_keys(%__MODULE__{}) :: list()
  def get_unwritten_keys(%__MODULE__{data_keys: data_keys, file_keys: file_keys}) do
    data_keys ++ file_keys
  end

  defp eliminate_written_data(%__MODULE__{data_keys: []} = state), do: state

  defp eliminate_written_data(%__MODULE__{data_keys: data_keys, db: db} = state) do
    data_keys
    |> Enum.reject(&CubDB.has_key?(db, &1))
    |> then(&%{state | data_keys: &1})
  end

  defp eliminate_written_files(%__MODULE__{file_keys: []} = state), do: state

  defp eliminate_written_files(%__MODULE__{file_keys: file_keys, db: db} = state) do
    path = CubDB.data_dir(db) <> "_files"

    file_keys
    |> Enum.reject(fn {:file_chunk, file_key, a, b} ->
      Chat.FileFs.has_file?({file_key, a, b}, path)
    end)
    |> then(&%{state | file_keys: &1})
  end

  defp update_compete(%__MODULE__{data_count: data_count, file_count: file_count} = state) do
    %{state | complete?: data_count + file_count == 0}
  end

  defp update_counts(%__MODULE__{data_keys: data_keys, file_keys: file_keys} = state) do
    %{state | data_count: Enum.count(data_keys), file_count: Enum.count(file_keys)}
  end
end
