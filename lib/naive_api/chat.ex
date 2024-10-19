defmodule NaiveApi.Chat do
  @moduledoc "Chat resolvers"
  use NaiveApi, :resolver
  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.User

  @default_amount 20

  def read(_, %{peer_public_key: peer_public_key, my_keypair: my_keypair} = params, _) do
    peer = User.by_id(peer_public_key)
    my_card = User.by_id(my_keypair.public_key)
    me = Identity.from_keys(my_keypair) |> Map.put(:name, my_card.name)
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

  def send_text(
        _,
        %{
          peer_public_key: peer_public_key,
          my_keypair: my_keypair,
          text: text,
          timestamp: timestamp
        },
        _
      ) do
    peer = User.by_id(peer_public_key)
    me = Identity.from_keys(my_keypair)
    dialog = Dialogs.find_or_open(me, peer)

    case String.trim(text) do
      "" ->
        ["Can't write empty text"] |> error()

      content ->
        {index, %{id: id}} =
          content
          |> Messages.Text.new(timestamp)
          |> Dialogs.add_new_message(me, dialog)
          |> MemoIndex.add(dialog, me)

        %{id: id, index: index}
        |> ok()
    end
  end

  defp author_card(%{is_mine?: false}, _me, peer), do: peer
  defp author_card(_message, me, _peer), do: me |> Card.from_identity()
end
