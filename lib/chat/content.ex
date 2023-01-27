defmodule Chat.Content do
  @moduledoc "Content handling functions common for dialogs and rooms"

  alias Chat.{
    Files,
    Memo,
    RoomInvites
  }

  alias Chat.Utils.StorageId

  def delete(%{content: json, type: :room_invite}),
    do: json |> StorageId.from_json() |> RoomInvites.delete()

  def delete(%{content: json, type: :memo}),
    do: json |> StorageId.from_json() |> Memo.delete()

  def delete(%{content: json, type: type}) when type in [:audio, :file, :image, :video] do
    json |> StorageId.from_json() |> Files.delete()
  end

  def delete(_), do: :ok
end
