defmodule Chat.Broadcast.Topic do
  @moduledoc "Broadcast topics"

  def lobby, do: "chat::lobby"

  def dialog(x) do
    cond do
      match?(%Chat.Dialogs.Dialog{}, x) -> x |> Chat.Dialogs.key() |> Base.encode16(case: :lower)
      String.match?(x, ~r/^[0-9a-f]{64}$/i) -> x
      is_binary(x) -> x |> Base.encode16(case: :lower)
    end
    |> then(fn hex -> "dialog:#{hex}" end)
  end
end
