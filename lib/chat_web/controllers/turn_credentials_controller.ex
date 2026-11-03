defmodule ChatWeb.TurnCredentialsController do
  use ChatWeb, :controller

  alias Chat.Pq.ReadGate
  alias Chat.Turn.Config
  alias Chat.Turn.Credentials

  def create(conn, params) do
    if Config.enabled?() do
      issue_credentials(conn, params)
    else
      conn
      |> put_status(503)
      |> json(%{error: "turn_unavailable"})
    end
  end

  def options(conn, _params), do: send_resp(conn, 204, "")

  defp issue_credentials(conn, params) do
    params["user_hash"]
    |> ReadGate.verify_user(params["challenge_id"], params["signature"])
    |> case do
      {:ok, _sign_pkey} ->
        {username, credential, ttl} = Credentials.issue()

        json(conn, %{
          username: username,
          credential: credential,
          ttl: ttl,
          uris: Config.uris()
        })

      {:error, reason} ->
        reject(conn, reason)
    end
  end

  defp reject(conn, reason) do
    {status, body} =
      case reason do
        :invalid_challenge ->
          {401, %{error: "Invalid or expired challenge"}}

        :unknown_user ->
          {401, %{error: "unknown_user"}}

        :invalid_signature ->
          {401, %{error: "invalid_signature"}}
      end

    conn
    |> put_status(status)
    |> json(body)
  end
end
