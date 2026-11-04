defmodule ChatWeb.TurnCredentialsController do
  use ChatWeb, :controller

  alias Chat.Pq.ReadGate
  alias Chat.Turn.Config
  alias Chat.Turn.Credentials
  alias Chat.Turn.LanRelay
  alias Chat.Turn.RateLimiter

  def create(conn, params) do
    case relay_uris(conn) do
      {:ok, uris} ->
        issue_credentials(conn, params, uris)

      :unavailable ->
        conn
        |> put_status(503)
        |> json(%{error: "turn_unavailable"})
    end
  end

  def options(conn, _params), do: send_resp(conn, 204, "")

  defp relay_uris(conn) do
    case Config.mode() do
      :server ->
        if Config.enabled?(), do: {:ok, Config.uris()}, else: :unavailable

      :lan ->
        %{address: local_ip} = get_sock_data(conn)
        if LanRelay.active?(local_ip), do: {:ok, [Config.lan_uri(local_ip)]}, else: :unavailable
    end
  end

  defp issue_credentials(conn, params, uris) do
    case RateLimiter.check_and_increment(conn.remote_ip) do
      :ok ->
        authenticate_and_issue(conn, params, uris)

      {:error, retry_after} ->
        conn
        |> put_status(429)
        |> json(%{error: "rate_limited", retry_after: retry_after})
    end
  end

  defp authenticate_and_issue(conn, params, uris) do
    params["user_hash"]
    |> ReadGate.verify_user(params["challenge_id"], params["signature"])
    |> case do
      {:ok, _sign_pkey} ->
        {username, credential, ttl} = Credentials.issue()

        json(conn, %{
          username: username,
          credential: credential,
          ttl: ttl,
          uris: uris
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
