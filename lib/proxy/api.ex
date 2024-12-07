defmodule Proxy.Api do
  @moduledoc "Proxy API. For server controller"

  alias Chat.Proto.Identify

  @known_atoms %{
    users: :"users\0",
    dialog_message: true
  }
  @doc "Ensure atoms are loaded for deserialization"
  def known_atoms, do: @known_atoms

  def confirmation_token do
    token = :crypto.strong_rand_bytes(80)
    key = Chat.Broker.store(token)

    %{token_key: key, token: token} |> wrap()
  end

  def register_user(args) do
    %{
      name: name,
      public_key: public_key
    } = args |> unwrap_map_by(fn %{public_key: key} -> key end)

    card = Chat.Card.new(name, public_key)
    Chat.User.register(card)
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

    Chat.Dialogs.find_or_open(me, peer) |> wrap()
  catch
    # x, y -> {:wrong_args, x, y, __STACKTRACE__} |> dbg()
    _, _ -> :wrong_args |> wrap()
  end

  def save_parcel(args) do
    %{
      author: me,
      parcel: parcel
    } = args |> unwrap_map_by(fn %{author: me} -> Identify.pub_key(me) end)

    true = Chat.SignedParcel.sign_valid?(parcel, Identify.pub_key(me))
    true = Chat.SignedParcel.scope_valid?(parcel, Identify.pub_key(me))

    indexed_parcel = Chat.SignedParcel.inject_next_index(parcel)
    data_items = Chat.SignedParcel.data_items(indexed_parcel)

    Enum.each(data_items, fn {key, value} -> Chat.Db.put(key, value) end)

    data_keys = data_items |> Enum.map(fn {key, _} -> key end)
    Chat.Db.Copying.await_written_into(data_keys, Chat.Db.db())

    indexed_parcel
    |> Chat.SignedParcel.prepare_for_broadcast()
    |> broadcast()

    :ok |> wrap()
  catch
    # x, y -> {:wrong_args, x, y, __STACKTRACE__} |> dbg() |> wrap()
    _, _ -> :wrong_args |> wrap()
  end

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
      {:new_dialog_message, key, indexed_message} ->
        Chat.Broadcast.new_dialog_message(indexed_message, key)

      {:new_user, card} ->
        Chat.Broadcast.new_user(card)

      _ ->
        :skip
    end
  end

  ############
  # Utilities
  defp correct_digest?(token_key, public_key, digest) do
    token = Chat.Broker.get(token_key)
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
      :users -> &Chat.Db.values/2
      _ -> &Chat.Db.select/2
    end
  end
end
