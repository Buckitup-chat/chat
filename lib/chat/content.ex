defmodule Chat.Content do
  @moduledoc "Content handling functions common for dialogs and rooms"

  alias Chat.{
    Files,
    Images,
    Memo
  }

  alias Chat.Utils.StorageId

  def delete(%{content: json, type: :image}),
    do: json |> StorageId.from_json() |> Images.delete()

  def delete(%{content: json, type: :memo}),
    do: json |> StorageId.from_json() |> Memo.delete()

  def delete(%{content: json, type: :file}),
    do: json |> StorageId.from_json() |> Files.delete()

  def delete(_), do: :ok
end
