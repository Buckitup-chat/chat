defmodule Proxy do
  @moduledoc "Proxy. Client side"

  alias Chat.DbKeys

  # Users
  def register_me(server, me) do
    %{
      public_key: me.public_key,
      name: me.name
    }
    |> add_signed_token(server, me.private_key)
    |> api_register_user(server)
  catch
    _, _ -> :failed
  end

  def get_users(server) do
    api_select(server, min: {:users, 0}, max: {:"users\0", 0}, amount: 10_000)
  end

  # Dialogs
  def find_or_create_dialog(server, me, peer) do
    %{
      me: me |> Chat.Card.from_identity(),
      peer: peer
    }
    |> add_signed_token(server, me.private_key)
    |> api_create_dialog(server)
  end

  def get_dialog_messages(server, dialog, index, amount) do
    dialog_key = Chat.Dialogs.key(dialog)

    api_select(server,
      min: {:dialog_message, dialog_key, 0, 0},
      max: {:dialog_message, dialog_key, index, nil},
      amount: amount
    )
  end

  def get_dialog_message(server, dialog, index, id) do
    dialog_key = Chat.Dialogs.key(dialog)

    api_key_value(server, {:dialog_message, dialog_key, index, id |> Enigma.hash()})
  end

  # Rooms
  def get_rooms(server) do
    api_select(server, min: DbKeys.room_min(), max: DbKeys.room_max(), amount: 10_000)
  end

  def request_room(server, me, room_key) do
    %{
      me: me |> Chat.Card.from_identity(),
      room_pub_key: room_key
    }
    |> add_signed_token(server, me.private_key)
    |> api_request_room_access(server)
  end

  def approve_room_request(server, me, {room_key, user_key, ciphered_room_identity}) do
    %{
      room_pub_key: room_key,
      requester_key: user_key,
      ciphered_room_identity: ciphered_room_identity
    }
    |> add_signed_token(server, me.private_key)
    |> api_approve_room_request(server)
  end

  def clean_room_request(server, me, room_key) do
    %{
      room_pub_key: room_key,
      me: me |> Chat.Card.from_identity()
    }
    |> add_signed_token(server, me.private_key)
    |> api_clean_room_request(server)
  end

  # Content
  def save_parcel(parcel, server, me) do
    %{
      parcel: parcel,
      author: me.public_key
    }
    |> add_signed_token(server, me.private_key)
    |> api_save_parcel(server)
  end

  def get_file_info(server, file_key) do
    api_key_value(server, {:file, file_key})
  end

  def get_file_secrets(server, file_key) do
    api_key_value(server, {:file_secrets, file_key})
  end

  def read_file_chunk(server, file_key, start) do
    api_key_value(server, {:file_chunk, file_key, start})
  end

  def get_data_by_keys(server, keys) do
    api_bulk_get(server, keys |> Enum.uniq())
  end

  defp add_signed_token(params, server, private_key) do
    %{token_key: token_key, token: token} = api_confirmation_token(server)

    %{
      token_key: token_key,
      digest: Enigma.sign(token, private_key)
    }
    |> Map.merge(params)
  end

  # Terminology
  ####################################
  defp api_confirmation_token(server), do: api_get(server, "confirmation-token", [])
  defp api_select(server, args), do: api_get(server, "select", args)
  defp api_key_value(server, args), do: api_get(server, "key-value", args)
  defp api_bulk_get(server, args), do: api_post(server, "bulk-get", args)
  defp api_register_user(args, server), do: api_post(server, "register-user", args)
  defp api_create_dialog(args, server), do: api_post(server, "create-dialog", args)
  defp api_save_parcel(args, server), do: api_post(server, "save-parcel", args)
  defp api_request_room_access(args, server), do: api_post(server, "request-room-access", args)
  defp api_approve_room_request(args, server), do: api_post(server, "approve-room-request", args)
  defp api_clean_room_request(args, server), do: api_post(server, "clean-room-request", args)

  #  Request utilities
  ####################################

  defp api_get(server, action, args) do
    # ["=== proxy GET", action, args] |> dbg()

    server
    |> build_url(action, args)
    |> HTTPoison.get([], follow_redirect: true)
    |> handle_respoonse()
  end

  defp api_post(server, action, args) do
    # ["=== proxy POST", action, args] |> dbg()

    server
    |> build_url(action, %{})
    |> HTTPoison.post(args |> Proxy.Serialize.serialize(), [], follow_redirect: true)
    |> handle_respoonse()
  end

  defp handle_respoonse(response) do
    case response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body |> unwrap()

      _ ->
        {:error, :no_server_responce}
    end
  end

  defp unwrap(x) do
    case(x) do
      str when is_binary(str) -> Proxy.Serialize.deserialize_with_atoms(str)
      x -> x
    end
  end

  defp build_url(server, action, args) do
    query_string =
      %{
        args: args |> Proxy.Serialize.serialize() |> Base.url_encode64(),
        t: System.monotonic_time(:millisecond)
      }
      |> URI.encode_query()

    "http://#{server}/proxy-api/#{action}"
    |> URI.new!()
    |> URI.append_query(query_string)
    |> URI.to_string()
  end
end
