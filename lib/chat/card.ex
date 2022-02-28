defmodule Chat.Card do
  @moduledoc "User/Room representation in registry"

  alias Chat.Identity
  alias Chat.Utils

  @derive {Inspect, only: [:name, :hash]}
  defstruct [:name, :hash, :pub_key]

  def from_identity(%Identity{name: name} = identity) do
    pub_key = identity |> Identity.pub_key()

    new(name, pub_key)
  end

  def new(name, pub_key) do
    %__MODULE__{
      hash: Utils.hash(pub_key),
      name: name,
      pub_key: pub_key
    }
  end
end
