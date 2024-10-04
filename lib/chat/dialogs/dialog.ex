defmodule Chat.Dialogs.Dialog do
  @moduledoc "Module to hold a conversation between A and B"

  alias Chat.Proto.Identify

  @derive {Inspect, only: []}
  defstruct [:a_key, :b_key]

  def start(some_peer, other_peer) do
    some_key = some_peer |> Identify.pub_key()
    other_key = other_peer |> Identify.pub_key()

    %__MODULE__{
      a_key: max(some_key, other_key),
      b_key: min(some_key, other_key)
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
