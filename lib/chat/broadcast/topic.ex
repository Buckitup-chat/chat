defmodule Chat.Broadcast.Topic do
  @moduledoc "Broadcast topics"

  def lobby, do: "chat::lobby"

  def dialog(x) do
    cond do
      match?(%Chat.Dialogs.Dialog{}, x) -> x |> Chat.Dialogs.key() |> to_hex()
      String.match?(x, ~r/^[0-9a-f]{64}$/i) -> x
      is_binary(x) -> x |> to_hex()
    end
    |> then(fn hex -> "dialog:#{hex}" end)
  end

  def user_room_approval(user_key) do
    "chat::user_room_approval:#{user_key |> to_hex()}"
  end

  def login(user_identity) do
    "login:" <> (user_identity |> Enigma.hash() |> to_hex())
  end

  defp to_hex(x), do: x |> Base.encode16(case: :lower)
end
