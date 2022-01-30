defmodule Chat.User.Card do
  @moduledoc "User representation in registry"

  alias Chat.User.Identity

  @derive {Inspect, only: [:name, :id]}
  defstruct [:name, :id, :pub_key]

  def from_identity(%Identity{} = identity) do
    %__MODULE__{
      id: UUID.uuid4(),
      name: identity.name,
      pub_key: Identity.pub_key(identity)
    }
  end
end
