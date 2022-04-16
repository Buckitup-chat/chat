defmodule Chat.Dialogs.Dialog do
  @moduledoc "Module to hold a conversation between A and B"

  alias Chat.Db
  alias Chat.Dialogs.Message
  alias Chat.Dialogs.PrivateMessage
  alias Chat.Images

  alias Chat.Card
  alias Chat.Identity
  alias Chat.Utils

  @derive {Inspect, only: []}
  defstruct [:a_key, :b_key]

  def start(%Identity{} = a, %Card{pub_key: b_key}) do
    %__MODULE__{
      a_key: a |> Identity.pub_key(),
      b_key: b_key
    }
  end

  def add_text(
        %__MODULE__{} = dialog,
        %Identity{} = source,
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

  def read(%Message{} = msg, identitiy, side) when side in [:a_copy, :b_copy] do
    is_mine? = (side == :a_copy and msg.is_a_to_b?) or (side == :b_copy and !msg.is_a_to_b?)

    %PrivateMessage{
      timestamp: msg.timestamp,
      type: msg.type,
      id: msg.id,
      is_mine?: is_mine?,
      content: msg[side] |> Utils.decrypt(identitiy)
    }
  end

  def read(
        %__MODULE__{} = dialog,
        %Identity{} = me,
        before,
        amount
      ) do
    side = dialog |> my_side(me)

    dialog
    |> get_messages(before, amount)
    |> Enum.map(&read(&1, me, side))
    |> Enum.reverse()
  end

  def my_side(%__MODULE__{a_key: a_key, b_key: b_key}, identitiy) do
    case identitiy |> Identity.pub_key() do
      ^a_key -> :a_copy
      ^b_key -> :b_copy
      _ -> raise "unknown_user_in_dialog"
    end
  end

  defp add_message(
         %__MODULE__{a_key: a_key, b_key: b_key} = dialog,
         %Identity{} = source,
         content,
         opts
       ) do
    a_copy = content |> Utils.encrypt(a_key)
    b_copy = content |> Utils.encrypt(b_key)

    dialog
    |> my_side(source)
    |> case do
      :a_copy -> Message.a_to_b(a_copy, b_copy, opts)
      :b_copy -> Message.b_to_a(a_copy, b_copy, opts)
    end
    |> tap(fn %{id: id, timestamp: time} = msg -> dialog |> msg_key(time, id) |> Db.put(msg) end)
  end

  defp get_messages(dialog, {time, id}, amount) do
    {
      msg_key(dialog, 0, 0),
      msg_key(dialog, time, id)
    }
    |> Db.values(amount)
  end

  defp msg_key(%__MODULE__{} = dialog, time, 0),
    do: {:dialog_message, dialog |> dialog_key(), time, 0}

  defp msg_key(%__MODULE__{} = dialog, time, id),
    do: {:dialog_message, dialog |> dialog_key(), time, id |> Utils.binhash()}

  def dialog_key(%__MODULE__{a_key: a_key, b_key: b_key}) do
    [a_key, b_key]
    |> Enum.map(&Utils.hash/1)
    |> Enum.sort()
    |> Enum.join()
    |> Utils.hash()
    |> Utils.binhash()
  end
end
