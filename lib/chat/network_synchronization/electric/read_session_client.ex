defmodule Chat.NetworkSynchronization.Electric.ReadSessionClient do
  @moduledoc """
  Opens a read session on a peer (see `pq_access_gating` § Read Gating).

  Signs the peer's one-time challenge with this device's server identity and
  exchanges it for a per-shape Bearer token. Same PoP as ingest.
  """

  alias Chat.Pq.ServerIdentity

  @timeout 10_000

  @doc """
  Returns `{:ok, token, expires_in_seconds}` or `{:error, reason}` where reason is
  `:not_in_trust_chain`, `:unknown_user`, `{:http, status, body}` or a transport error.
  """
  def open(peer_url, shape) do
    with {:ok, challenge_id, challenge} <- fetch_challenge(peer_url) do
      "#{peer_url}/electric/v1/read_session"
      |> Req.post(
        json: %{
          user_hash: ServerIdentity.user_hash(),
          shape: to_string(shape),
          challenge_id: challenge_id,
          signature: sign(challenge)
        },
        receive_timeout: @timeout,
        retry: false
      )
      |> case do
        {:ok, %{status: 200, body: %{"token" => token, "expires_in" => expires_in}}} ->
          {:ok, token, expires_in}

        {:ok, %{status: 403, body: %{"error" => "not_in_trust_chain"}}} ->
          {:error, :not_in_trust_chain}

        {:ok, %{status: 401, body: %{"error" => "unknown_user"}}} ->
          {:error, :unknown_user}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, _} = error ->
          error
      end
    end
  end

  defp fetch_challenge(peer_url) do
    "#{peer_url}/electric/v1/challenge"
    |> Req.get(receive_timeout: @timeout, retry: false)
    |> case do
      {:ok, %{status: 200, body: %{"challenge_id" => id, "challenge" => challenge}}} ->
        {:ok, id, challenge}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, _} = error ->
        error
    end
  end

  defp sign(challenge) do
    challenge
    |> EnigmaPq.sign(ServerIdentity.get().sign_skey)
    |> Base.encode64(padding: false)
  end
end
