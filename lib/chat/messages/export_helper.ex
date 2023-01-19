defmodule Chat.Messages.ExportHelper do
  @moduledoc """
  Helper for message export
  """

  def get_filename(name, id) do
    {extension, filename} =
      name
      |> String.split(".")
      |> List.pop_at(-1)

    Enum.join(filename, ".") <> "_" <> id <> "." <> extension
  end
end
