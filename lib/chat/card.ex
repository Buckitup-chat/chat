defmodule Chat.Card do
  @moduledoc "User/Room? representation in registry"

  use StructAccess

  alias Chat.Identity

  @derive {Inspect, only: [:name]}
  defstruct [:name, :pub_key]

  def from_identity(%Identity{name: name} = identity) do
    pub_key = identity |> Identity.pub_key()

    new(name, pub_key)
  end

  def new(name, pub_key) do
    %__MODULE__{
      name: name,
      pub_key: pub_key
    }
  end

  def pub_key(%__MODULE__{pub_key: pub_key}), do: pub_key
end

defimpl Enigma.Hash.Protocol, for: Chat.Card do
  def to_iodata(card), do: card.pub_key
end
