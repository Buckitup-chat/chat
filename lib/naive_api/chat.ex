defmodule NaiveApi.Chat do
  @moduledoc "Chat resolvers"
  use NaiveApi, :resolver
  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.User

  @default_amount 20

  def read(_, %{peer_public_key: peer_public_key, my_keypair: my_keypair} = params, _) do
    peer = User.by_id(peer_public_key)
    me = Identity.from_keys(my_keypair)
    dialog = Dialogs.find_or_open(me, peer)

    before_timestamp = params[:before]
    amount = params[:amount] || @default_amount

    dialog
    |> Dialogs.read(me, {before_timestamp, 0}, amount)
    |> Enum.map(fn message ->
      author = author_card(message, me, peer)
      Map.put(message, :author, author)
    end)
    |> ok()
  end

  defp author_card(%{is_mine?: false}, _me, peer), do: peer
  defp author_card(_message, me, _peer), do: me |> Card.from_identity()
end
