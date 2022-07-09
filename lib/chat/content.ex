defmodule Chat.Content do
  @moduledoc "Content handling functions common for dialogs and rooms"

  alias Chat.{
    Files,
    Images,
    Memo,
    RoomInvites
  }

  alias Chat.Utils.StorageId

  def delete(%{content: json, type: :room_invite}),
    do: json |> StorageId.from_json() |> RoomInvites.delete()

  def delete(%{content: json, type: :image}) do
    json |> StorageId.from_json() |> Images.delete()
    json |> StorageId.from_json() |> Files.delete()
  end

  def delete(%{content: json, type: :memo}),
    do: json |> StorageId.from_json() |> Memo.delete()

  def delete(%{content: json, type: :file}),
    do: json |> StorageId.from_json() |> Files.delete()

  def delete(_), do: :ok
end
