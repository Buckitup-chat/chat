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
    broadcast_new_user(card)

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

  defp broadcast_new_user(card) do
    Chat.Broadcast.new_user(card)
  end

  defp choose_getter(slug) do
    case slug do
      :users -> &Chat.Db.values/2
      _ -> &Chat.Db.select/2
    end
  end
end
