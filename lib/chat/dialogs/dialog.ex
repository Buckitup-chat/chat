defmodule Chat.Dialogs.Dialog do
  @moduledoc "Module to hold a conversation between A and B"

  alias Chat.Images
  alias Chat.User

  alias Chat.Dialogs.Message
  alias Chat.Dialogs.PrivateMessage

  @derive {Inspect, only: [:messages]}
  defstruct [:a_key, :b_key, :messages]

  def start(%Chat.Identity{} = a, %Chat.Card{} = b) do
    %__MODULE__{
      a_key: a |> User.pub_key(),
      b_key: b |> User.pub_key(),
      messages: []
    }
  end

  def add_text(
        %__MODULE__{} = dialog,
        %Chat.Identity{} = source,
        text,
        now
      ) do
    add_message(dialog, source, text, now: now, type: :text)
  end

  def add_image(
        %__MODULE__{} = dialog,
        %Chat.Identity{} = source,
        data,
        now
      ) do
    {key, secret} = Images.add(data)

    msg =
      %{key => secret |> Base.url_encode64()}
      |> Jason.encode!()

    add_message(dialog, source, msg, now: now, type: :image)
  end

  def read(
        %__MODULE__{messages: messages, a_key: a_key, b_key: b_key},
        %Chat.Identity{} = me,
        before,
        amount
      ) do
    side =
      case me |> User.pub_key() do
        ^a_key -> :a_copy
        ^b_key -> :b_copy
        _ -> raise "unknown_user_in_dialog"
      end

    messages
    |> Chat.Utils.page(before, amount)
    |> Enum.map(fn msg ->
      is_mine? = (side == :a_copy and msg.is_a_to_b?) or (side == :b_copy and !msg.is_a_to_b?)

      %PrivateMessage{
        timestamp: msg.timestamp,
        type: msg.type,
        is_mine?: is_mine?,
        content: msg[side] |> User.decrypt(me)
      }
    end)
  end

  def glimpse(%__MODULE__{messages: [last | _]} = dialog) do
    %{dialog | messages: [last]}
  end

  defp add_message(
         %__MODULE__{a_key: a_key, b_key: b_key} = dialog,
         %Chat.Identity{} = source,
         msg,
         opts
       ) do
    new_messsage =
      case source |> User.pub_key() do
        ^a_key -> Message.a_to_b(User.encrypt(msg, a_key), User.encrypt(msg, b_key), opts)
        ^b_key -> Message.b_to_a(User.encrypt(msg, a_key), User.encrypt(msg, b_key), opts)
        _ -> raise "unknown_user_in_dialog"
      end

    %{dialog | messages: [new_messsage | dialog.messages]}
  end
end
