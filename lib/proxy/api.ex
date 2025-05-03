defmodule Proxy.Api do
  @moduledoc "Proxy API. For server controller"

  alias Chat
  alias Chat.Broadcast
  alias Chat.Broker
  alias Chat.Card
  alias Chat.Db
  alias Chat.Db.Copying
  alias Chat.Dialogs
  alias Chat.Log
  alias Chat.Proto.Identify
  alias Chat.Rooms
  alias Chat.SignedParcel
  alias Chat.User

  def confirmation_token do
    token = :crypto.strong_rand_bytes(80)
    key = Broker.store(token)

    %{token_key: key, token: token} |> wrap()
  end

  def confirmation_token(_), do: confirmation_token()

  def register_user(args) do
    %{
      name: name,
      public_key: public_key
    } = args |> unwrap_map_by(fn %{public_key: key} -> key end)

    card = Card.new(name, public_key)
    User.register(card)
    {:new_user, card} |> broadcast()

    card |> wrap()
  catch
    _, _ -> :wrong_args |> wrap()
  end

  def create_dialog(args) do
    %{
      me: me,
      peer: peer
    } = args |> unwrap_map_by(fn %{me: me} -> Identify.pub_key(me) end)

    Dialogs.find_or_open(me, peer) |> wrap()
  catch
    # x, y -> {:wrong_args, x, y, __STACKTRACE__} |> dbg()
    _, _ -> :wrong_args |> wrap()
  end

  def save_parcel(args) do
    %{
      author: me,
      parcel: parcel
    } = args |> unwrap_map_by(fn %{author: me} -> Identify.pub_key(me) end)

    true = SignedParcel.sign_valid?(parcel, Identify.pub_key(me))
    true = SignedParcel.scope_valid?(parcel, Identify.pub_key(me))

    indexed_parcel = SignedParcel.inject_next_index(parcel)
    data_items = SignedParcel.data_items(indexed_parcel)

    Enum.each(data_items, fn {key, value} -> Db.put(key, value) end)

    data_keys = data_items |> Enum.map(fn {key, _} -> key end)
    Copying.await_written_into(data_keys, Db.db())

    indexed_parcel
    |> SignedParcel.prepare_for_broadcast()
    |> broadcast()

    :ok |> wrap()
  catch
    _, _ -> :wrong_args |> wrap()
  end

  def request_room_access(args) do
    %{
      room_pub_key: room_key,
      me: requester_card
    } = args |> unwrap_map_by(fn %{me: card} -> Identify.pub_key(card) end)

    requester_pub_key = Identify.pub_key(requester_card)
    time = DateTime.utc_now() |> DateTime.to_unix()

    room =
      Rooms.add_request(room_key, requester_pub_key, time, fn req_message ->
        # Page.Room.broadcast_new_message(req_message, room_key, me, time)
        req_message |> dbg()
      end)

    Rooms.RoomsBroker.put(room)
    Broadcast.room_requested(room, requester_pub_key)
    Log.request_room_key(requester_pub_key, time, room.pub_key)

    :ok |> wrap()
  catch
    _, _ -> :wrong_args |> wrap()
  end

  def approve_room_request(args) do
    %{
      room_pub_key: room_key,
      requester_key: user_key,
      ciphered_room_identity: ciphered_room_identity,
      me: approver_card
    } = args |> unwrap_map_by(fn %{me: card} -> Identify.pub_key(card) end)

    approver_pub_key = Identify.pub_key(approver_card)
    time = DateTime.utc_now() |> DateTime.to_unix()

    room =
      Rooms.approve_request(room_key, user_key, ciphered_room_identity, public_only: true)

    Rooms.RoomsBroker.put(room)

    Log.approve_room_request(approver_pub_key, time, room.pub_key)

    :ok |> wrap()
  catch
    _, _ -> :wrong_args |> wrap()
  end

  def clean_room_request(args) do
    %{
      room_pub_key: room_key,
      me: requester_card
    } = args |> unwrap_map_by(fn %{me: card} -> Identify.pub_key(card) end)

    requester_pub_key = Identify.pub_key(requester_card)

    room = Rooms.clear_approved_request(room_key, requester_pub_key)
    Rooms.RoomsBroker.put(room)

    :ok |> wrap()
  catch
    _, _ -> :wrong_args |> wrap()
  end

  # General
  def select_data(args) do
    %{min: min, max: max, amount: amount} = args |> unwrap_map()

    getter =
      min
      |> elem(0)
      |> choose_getter()

    getter.({min, max}, amount)
    |> Enum.to_list()
    |> wrap()
  catch
    _, _ -> :wrong_args |> wrap()
  end

  def bulk_get_data(args) do
    args
    |> unwrap()
    |> Map.new(fn key -> {key, Db.get(key)} end)
    |> wrap()
  catch
    _, _ -> :wrong_args |> wrap()
  end

  def key_value_data(args) do
    args
    |> unwrap()
    |> Chat.db_get()
    |> wrap()
  catch
    _, _ -> :wrong_args |> wrap()
  end

  def broadcast(msg) do
    case msg do
      {:new_dialog_message, dialog_key, indexed_message} ->
        Broadcast.new_dialog_message(indexed_message, dialog_key)

      {:new_user, card} ->
        Broadcast.new_user(card)

      _ ->
        :skip
    end
  end

  ############
  # Utilities
  defp correct_digest?(token_key, public_key, digest) do
    token = Broker.get(token_key)
    Enigma.valid_sign?(digest, token, public_key)
  end

  defp unwrap(x) do
    if is_binary(x),
      do: Proxy.Serialize.deserialize(x),
      else: x
  end

  defp unwrap_map(x), do: x |> unwrap() |> Map.new()

  defp unwrap_map_by(args, owner_pub_key_getter) do
    map = %{digest: digest, token_key: token_key} = unwrap_map(args)
    true = correct_digest?(token_key, owner_pub_key_getter.(map), digest)
    map
  end

  defp wrap(x), do: Proxy.Serialize.serialize(x)

  defp choose_getter(slug) do
    case slug do
      :users -> &Db.values/2
      :rooms -> &Db.values/2
      _ -> &Db.select/2
    end
  end
end
