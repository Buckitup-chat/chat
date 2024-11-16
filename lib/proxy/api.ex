defmodule Proxy.Api do
  @moduledoc "Proxy API. For server controller"

  alias Chat.Proto.Identify

  @known_atoms %{
    users: :"users\0",
    dialog_message: true
  }
  def known_atoms, do: @known_atoms

  def confirmation_token do
    token = :crypto.strong_rand_bytes(80)
    key = Chat.Broker.store(token)

    %{token_key: key, token: token}
    |> Proxy.Serialize.serialize()
  end

  def correct_digest?(token_key, public_key, digest) do
    token = Chat.Broker.get(token_key)
    Enigma.valid_sign?(digest, token, public_key)
  end

  def register_user(args) do
    args
    |> case do
      binary when is_binary(binary) -> Proxy.Serialize.deserialize(binary)
      x -> x
    end
    |> Map.new()
    |> case do
      %{name: name, public_key: public_key, digest: digest, token_key: token_key} ->
        if correct_digest?(token_key, public_key, digest) do
          card = Chat.Card.new(name, public_key)
          Chat.User.register(card)
          broadcast_new_user(card)
        end

      _ ->
        :wrong_args
    end
    |> Proxy.Serialize.serialize()
  catch
    _, _ -> :wrong_args |> Proxy.Serialize.serialize()
  end

  def create_dialog(args) do
    args
    |> case do
      binary when is_binary(binary) -> Proxy.Serialize.deserialize(binary)
      x -> x
    end
    |> Map.new()
    |> case do
      %{me: me, peer: peer, digest: digest, token_key: token_key} ->
        if correct_digest?(token_key, Identify.pub_key(me), digest) do
          Chat.Dialogs.find_or_open(me, peer)
        end

      _ ->
        :wrong_args
    end
    |> Proxy.Serialize.serialize()
  catch
    # a, b ->
    #   [a, b, __STACKTRACE__] |> dbg()
    _, _ -> :wrong_args |> Proxy.Serialize.serialize()
  end

  def select_data(args) do
    args
    |> case do
      binary when is_binary(binary) -> Proxy.Serialize.deserialize(binary)
      x -> x
    end
    |> Map.new()
    |> case do
      %{min: min, max: max, amount: amount} ->
        getter =
          min
          |> elem(0)
          |> choose_getter()

        getter.({min, max}, amount)
        |> Enum.to_list()

      _ ->
        :wrong_args
    end
    |> Proxy.Serialize.serialize()
  catch
    _, _ -> :wrong_args |> Proxy.Serialize.serialize()
  end

  def key_value_data(args) do
    args
    |> case do
      binary when is_binary(binary) -> Proxy.Serialize.deserialize(binary)
      x -> x
    end
    |> Chat.db_get()
    |> Proxy.Serialize.serialize()
  catch
    _, _ -> :wrong_args |> Proxy.Serialize.serialize()
  end

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
