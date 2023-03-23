defmodule NaiveApi.Shared do
  @moduledoc "Additional resolvers"
  use NaiveApi, :resolver
  alias Chat.Card
  alias Chat.Identity

  def resolve_identity_keys(%Identity{} = identity, _, _) do
    {:ok, Map.put(identity, :keys, Map.take(identity, [:private_key, :public_key]))}
  end

  def resolve_card_key(%Card{} = card, _, _), do: {:ok, card.pub_key}
end
