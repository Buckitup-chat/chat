defmodule Chat.Messages.Text do
  @moduledoc ""

  defstruct text: "", timestamp: 0
end

defimpl Chat.DryStorable, for: Chat.Messages.Text do
  alias Chat.Memo
  alias Chat.Utils.StorageId

  def content(text) do
    case type(text) do
      :memo ->
        text.text
        |> Memo.add()
        |> StorageId.to_json()

      :text ->
        text.text
    end
  end

  def timestamp(text), do: text.timestamp

  @spec type(%Chat.Messages.Text{}) :: atom()
  def type(text) do
    if String.length(text.text) > 150 do
      :memo
    else
      :text
    end
  end
end
