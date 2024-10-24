defmodule Proxy do
  @moduledoc "Proxy. Client side"

  # Users
  def register_me(server, me) do
    %{token_key: token_key, token: token} =
      api_confirmation_token(server)

    digest = Enigma.sign(token, me.private_key)

    api_register_user(
      server,
      %{
        token_key: token_key,
        public_key: me.public_key,
        name: me.name,
        digest: digest
      }
    )
  catch
    _, _ -> :failed
  end

  def get_users(server) do
    api_select(server, min: {:users, 0}, max: {:"users\0", 0}, amount: 10000)
  end

  # Dialogs
  def find_or_create_dialog(server, me, peer) do
    %{token_key: token_key, token: token} =
      api_confirmation_token(server)

    digest = Enigma.sign(token, me.private_key)

    api_create_dialog(server, %{
      token_key: token_key,
      me: me |> Chat.Card.from_identity(),
      peer: peer,
      digest: digest
    })
  end

  def get_dialog_messages(server, dialog, index, amount) do
    dialog_key = Chat.Dialogs.key(dialog)

    api_select(server,
      min: {:dialog_message, dialog_key, 0, 0},
      max: {:dialog_message, dialog_key, index, nil},
      amount: amount
    )
  end

  # Content
  def get_file_info(server, file_key) do
    api_key_value(server, {:file, file_key})
  end

  def get_file_secrets(server, file_key) do
    api_key_value(server, {:file_secrets, file_key})
  end

  def read_file_chunk(server, file_key, start) do
    api_key_value(server, {:file_chunk, file_key, start})
  end

  # Terminology
  ####################################
  defp api_confirmation_token(server), do: api_get(server, "confirmation-token", [])
  defp api_select(server, args), do: api_get(server, "select", args)
  defp api_key_value(server, args), do: api_get(server, "key-value", args)
  defp api_register_user(server, args), do: api_post(server, "register-user", args)
  defp api_create_dialog(server, args), do: api_post(server, "create-dialog", args)

  # Utilities
  ####################################

  defp api_get(server, action, args) do
    server
    |> build_url(action, args)
    |> HTTPoison.get()
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body |> unwrap()

      _ ->
        {:error, :no_server_responce}
    end
  end

  defp api_post(server, action, args) do
    server
    |> build_url(action, %{})
    |> HTTPoison.post(args |> Proxy.Serialize.serialize())
    |> case do
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
