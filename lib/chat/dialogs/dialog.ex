defmodule Chat.Dialogs.Dialog do
  @moduledoc "Module to hold a conversation between A and B"

  alias Chat.Images
  alias Chat.User

  alias Chat.Dialogs.Message
  alias Chat.Dialogs.PrivateMessage

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
        %__MODULE__{} = dialog,
        %User.Identity{} = source,
        text,
        now \\ DateTime.utc_now()
      ) do
    add_message(dialog, source, text, now: now, type: :text)
  end

  def add_image(
        %__MODULE__{} = dialog,
        %User.Identity{} = source,
        data,
        now \\ DateTime.utc_now()
      ) do
    {key, secret} = Images.add(data)

    msg =
      %{key => secret |> Base.encode64()}
      |> Jason.encode!()

    add_message(dialog, source, msg, now: now, type: :image)
  end

  def read(
        %__MODULE__{messages: messages, a_key: a_key, b_key: b_key},
        %User.Identity{} = me,
        before \\ DateTime.utc_now() |> DateTime.to_unix(),
        amount \\ 100
      ) do
    side =
      case me |> User.pub_key() do
        ^a_key -> :a_copy
        ^b_key -> :b_copy
        _ -> raise "unknown_user_in_dialog"
      end

    messages
    |> Enum.reduce_while({[], nil, amount}, fn
      %{timestamp: last_timestamp} = msg, {acc, last_timestamp, amount} ->
        {:cont, {[msg | acc], last_timestamp, amount - 1}}

      _, {_, _, amount} = acc when amount < 1 ->
        {:halt, acc}

      %{timestamp: timestamp} = msg, {acc, _, amount} when timestamp < before ->
        {:cont, {[msg | acc], timestamp, amount - 1}}

      _, acc ->
        {:cont, acc}
    end)
    |> then(&elem(&1, 0))
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

  def peer_pub_key(%__MODULE__{a_key: a_key, b_key: b_key}, %User.Identity{} = me) do
    case me |> User.pub_key() do
      ^a_key -> b_key
      ^b_key -> a_key
      _ -> raise "unknown_user_in_dialog"
    end
  end

  def glimpse(%__MODULE__{messages: [last | _]} = dialog) do
    %{dialog | messages: [last]}
  end

  defp add_message(
         %__MODULE__{a_key: a_key, b_key: b_key} = dialog,
         %User.Identity{} = source,
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
