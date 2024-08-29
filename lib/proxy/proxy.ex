defmodule Proxy do
  @moduledoc "Proxy. Client side"

  def register_me(server, me) do
    nil
  end

  def get_users(server) do
    api_select(server, min: {:users, 0}, max: {:"users\0", 0}, amount: 10000)
  end

  defp api_select(server, args) do
    server
    |> select_url(args)
    |> HTTPoison.get()
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> Proxy.Serialize.deserialize_with_atoms()

      _ ->
        {:error, :no_server_responce}
    end
  end

  defp select_url(server, args) do
    query_string =
      %{
        args: args |> Proxy.Serialize.serialize() |> Base.url_encode64(),
        t: System.monotonic_time(:millisecond)
      }
      |> URI.encode_query()

    "http://#{server}/proxy-api/select"
    |> URI.new!()
    |> URI.append_query(query_string)
    |> URI.to_string()
  end
end
