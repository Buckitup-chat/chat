defmodule Chat.Card do
  @moduledoc "User/Room representation in registry"

  alias Chat.Identity
  alias Chat.Utils

  @derive {Inspect, only: [:name, :hash]}
  defstruct [:name, :hash, :pub_key]

  def from_identity(%Identity{} = identity) do
    pub_key = identity |> Identity.pub_key()

    %__MODULE__{
      hash: Utils.hash(pub_key),
      name: identity.name,
      pub_key: pub_key
    }
  end
end
