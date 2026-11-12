defmodule Chat.FileFs.Common do
  @moduledoc """
  Common filesystem functions
  """
  alias Chat.Storage.Unit

  @int_padding 20

  # FileFs sits next to the current CubDB, which `Chat.Storage.Default` points at
  def build_path(nil), do: Chat.Db.db() |> CubDB.data_dir() |> Unit.cub_files_dir()
  def build_path(str), do: str

  def key_path(binary_key, prefix) do
    key = binary_key |> Base.encode16(case: :lower)

    [prefix, hc(key), key] |> Path.join()
  end

  def offset_name(int) do
    int
    |> to_string()
    |> String.pad_leading(@int_padding, "0")
  end

  def hc(str), do: String.slice(str, 0, 2)

  def binread(path) do
    path
    |> IO.binread(:eof)
    |> case do
      :eof -> ""
      str -> str
    end
  end
end
