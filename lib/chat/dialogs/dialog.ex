defmodule Chat.Dialogs.Dialog do
  @moduledoc "Module to hold a conversation between A and B"

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

  def dialog_key(%__MODULE__{a_key: a_key, b_key: b_key}) do
    [a_key, b_key]
    |> Enum.map(&Utils.hash/1)
    |> Enum.sort()
    |> Enum.join()
    |> Utils.hash()
    |> Utils.binhash()
  end
end
