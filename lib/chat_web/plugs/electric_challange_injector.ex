defmodule ChatWeb.Plugs.ElectricChallengeInjector do
  @moduledoc "Injects a fresh challenge into the response"

  import Plug.Conn

  alias Chat.Challenge

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> register_before_send(&inject_challenge/1)
  end

  defp inject_challenge(conn) do
    case conn.status do
      status when status in 200..299 ->
        {challenge_id, challenge} = Challenge.store()

        conn
        |> put_resp_header("x-challenge-id", challenge_id)
        |> put_resp_header("x-challenge", challenge)

      _ ->
        conn
    end
  end
end
