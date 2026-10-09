defmodule ChatWeb.ReadSessionController do
  use ChatWeb, :controller

  alias Chat.Pq.ReadGate
  alias Chat.Pq.ReadSession

  def create(conn, params) do
    params["user_hash"]
    |> ReadGate.open_session(params["shape"], params["challenge_id"], params["signature"])
    |> case do
      {:ok, token, shape} ->
        json(conn, %{token: token, shape: shape, expires_in: ReadSession.ttl_seconds()})

      {:error, reason} ->
        reject(conn, reason)
    end
  end

  def options(conn, _params), do: send_resp(conn, 204, "")

  defp reject(conn, reason) do
    {status, body} =
      case reason do
        :unknown_shape ->
          {400, %{error: "unknown_shape"}}

        :invalid_challenge ->
          {401, %{error: "Invalid or expired challenge"}}

        :unknown_user ->
          {401, %{error: "unknown_user"}}

        :invalid_signature ->
          {401, %{error: "invalid_signature"}}

        :not_in_trust_chain ->
          {403, %{error: "not_in_trust_chain", max_depth: ReadGate.max_depth()}}
      end

    conn
    |> put_status(status)
    |> json(body)
  end
end
