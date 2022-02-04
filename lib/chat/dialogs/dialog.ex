defmodule Chat.Dialogs.Dialog do
  @moduledoc "Module to hold a conversation between A and B"

  alias Chat.User

  alias Chat.Dialogs.Message

  @derive {Inspect, only: [:messages]}
  defstruct [:a_key, :b_key, :messages]

  def start(%User.Identity{} = a, %User.Card{} = b) do
    %__MODULE__{
      a_key: a |> User.pub_key(),
      b_key: b |> User.pub_key(),
      messages: []
    }
  end

  def add_text(
        %__MODULE__{a_key: a_key, b_key: b_key} = dialog,
        %User.Identity{} = source,
        text
      ) do
    new_messsage =
      case source |> User.pub_key() do
        ^a_key -> Message.a_to_b(User.encrypt(text, a_key), User.encrypt(text, b_key))
        ^b_key -> Message.b_to_a(User.encrypt(text, a_key), User.encrypt(text, b_key))
        _ -> raise "unknown_user_in_dialog"
      end

    %{dialog | messages: [new_messsage | dialog.messages]}
  end
end
