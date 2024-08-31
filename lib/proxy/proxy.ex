defmodule Proxy do
  @moduledoc "Proxy. Client side"

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

  defp api_confirmation_token(server), do: api_get(server, "confirmation-token", [])
  defp api_select(server, args), do: api_get(server, "select", args)
  defp api_register_user(server, args), do: api_post(server, "register-user", args)

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
      str when is_binary(str) -> Proxy.Serialize.deserialize(str)
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
