defmodule Chat.User.Card do
  @moduledoc "User representation in registry"

  alias Chat.User.Identity

  defstruct [:name, :id, :pub_key]

  def from_identity(%Identity{} = identity) do
    %__MODULE__{
      id: identity.id,
      name: identity.name,
      pub_key: Identity.pub_key(identity)
    }
  end
end
