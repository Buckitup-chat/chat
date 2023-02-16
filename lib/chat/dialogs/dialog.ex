defmodule Chat.Dialogs.Dialog do
  @moduledoc "Module to hold a conversation between A and B"

  alias Chat.Card
  alias Chat.Identity

  @derive {Inspect, only: []}
  defstruct [:a_key, :b_key]

  def start(%Identity{} = identity, %Card{pub_key: card_key}) do
    identity_key = Identity.pub_key(identity)

    %__MODULE__{
      a_key: max(identity_key, card_key),
      b_key: min(identity_key, card_key)
    }
  end
end

defimpl Enigma.Hash.Protocol, for: Chat.Dialogs.Dialog do
  alias Chat.Dialogs.Dialog

  def to_iodata(%Dialog{a_key: a, b_key: b}) do
    [a, b]
    |> Enum.sort()
    |> Enum.join()
  end
end

defimpl Jason.Encoder, for: Chat.Dialogs.Dialog do
  alias Chat.Dialogs.Dialog

  def encode(%Dialog{} = dialog, opts) do
    dialog
    |> Enigma.hash()
    |> Base.encode16(case: :lower)
    |> Jason.Encode.string(opts)
  end
end
