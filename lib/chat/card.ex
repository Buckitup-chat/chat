defmodule Chat.Card do
  @moduledoc "User/Room? representation in registry"

  use StructAccess

  alias Chat.Identity

  @derive {Inspect, only: [:name]}
  @derive {Jason.Encoder, only: [:name, :hash]}
  defstruct [:name, :pub_key, :hash]

  def from_identity(%Identity{name: name} = identity) do
    pub_key = identity |> Identity.pub_key()

    new(name, pub_key)
  end

  def new(name, pub_key) do
    %__MODULE__{
      name: name,
      pub_key: pub_key,
      hash: pub_key |> Base.encode16(case: :lower)
    }
  end
end

defimpl Enigma.Hash.Protocol, for: Chat.Card do
  def to_iodata(card), do: card.pub_key
end
