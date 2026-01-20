defmodule NaiveApi.Chat do
  @moduledoc "Chat resolvers"
  use NaiveApi, :resolver
  alias Chat.Card
  alias Chat.ChunkedFiles
  alias Chat.Dialogs
  alias Chat.FileIndex
  alias Chat.Identity
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.Upload.{Upload, UploadIndex}
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

  def send_file(
        _,
        %{peer_public_key: peer_public_key, my_keypair: my_keypair, upload_key: upload_key},
        _
      ) do
    peer = User.by_id(peer_public_key)
    me = Identity.from_keys(my_keypair)
    dialog = Dialogs.find_or_open(me, peer)

    case UploadIndex.get(upload_key) do
      nil ->
        ["Wrong upload key"] |> error()

      %Upload{} = upload ->
        decrypted_secret = ChunkedFiles.decrypt_secret(upload.encrypted_secret, me)

        {index, %{id: id}} =
          Messages.File.new(upload, upload_key, decrypted_secret, now())
          |> Dialogs.add_new_message(me, dialog)

        FileIndex.save(upload_key, dialog.a_key, id, decrypted_secret)
        FileIndex.save(upload_key, dialog.b_key, id, decrypted_secret)

        %{id: id, index: index}
        |> ok()
    end
  end

  defp author_card(%{is_mine?: false}, _me, peer), do: peer
  defp author_card(_message, me, _peer), do: me |> Card.from_identity()

  defp now, do: DateTime.utc_now() |> DateTime.to_unix()
end
