defmodule Chat.Dialogs.Dialog do
  @moduledoc "Module to hold a conversation between A and B"

  alias Chat.Card
  alias Chat.Identity
  alias Chat.Utils

  @derive {Inspect, only: []}
  defstruct [:a_key, :b_key]

  def start(%Identity{} = identity, %Card{pub_key: card_key}) do
    identity_key = Identity.pub_key(identity)

    %__MODULE__{
      a_key: max(identity_key, card_key),
      b_key: min(identity_key, card_key)
    }
  end

  def my_side(%__MODULE__{a_key: a_key, b_key: b_key}, identity) do
    case identity |> Identity.pub_key() do
      ^a_key -> :a_copy
      ^b_key -> :b_copy
      _ -> raise "unknown_user_in_dialog"
    end
  end

  def peer_key(%__MODULE__{a_key: key}, :b_copy), do: key
  def peer_key(%__MODULE__{b_key: key}, :a_copy), do: key

  def is_mine?(dialog, %{is_a_to_b?: is_a_to_b}, me) do
    dialog
    |> my_side(me)
    |> then(fn
      :a_copy -> is_a_to_b
      :b_copy -> !is_a_to_b
    end)
  end

  def dialog_key(%__MODULE__{} = dialog) do
    dialog
    |> dialog_hash()
    |> Utils.binhash()
  end

  def dialog_hash(%__MODULE__{a_key: a_key, b_key: b_key}) do
    [a_key, b_key]
    |> Enum.map(&Utils.hash/1)
    |> Enum.sort()
    |> Enum.join()
    |> Utils.hash()
  end
end

defimpl Jason.Encoder, for: Chat.Dialogs.Dialog do
  alias Chat.Dialogs.Dialog

  def encode(%Dialog{} = dialog, opts) do
    dialog
    |> Dialog.dialog_hash()
    |> Jason.Encode.string(opts)
  end
end
