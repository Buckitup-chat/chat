defmodule ChatWeb.Utils.IngestPop do
  @moduledoc """
  Reads the user Proof-of-Possession from an ingest body:
  `%{"auth" => %{"challenge_id" => id, "signature" => base64}}`.

  The challenge is consumed (single use). The signature is verified later by
  each shape's check against the mutation's own key.
  """

  alias Chat.Challenge

  @doc "Returns `{:ok, %{challenge, signature}}` or `{:error, {:unauthorized, msg}}`."
  def context(params) do
    with {:ok, challenge_id, signature_encoded} <- pop_from_body(params),
         {:ok, challenge} <- fetch_challenge(challenge_id),
         {:ok, signature} <- Base.decode64(signature_encoded, padding: false) do
      {:ok, %{challenge: challenge, signature: signature}}
    else
      :no_auth -> {:error, {:unauthorized, "Missing user PoP auth"}}
      :error -> {:error, {:unauthorized, "Invalid or expired challenge"}}
    end
  end

  defp pop_from_body(%{"auth" => %{"challenge_id" => challenge_id, "signature" => signature}})
       when is_binary(challenge_id) and is_binary(signature),
       do: {:ok, challenge_id, signature}

  defp pop_from_body(_params), do: :no_auth

  defp fetch_challenge(challenge_id) do
    case Challenge.get(challenge_id) do
      challenge when is_binary(challenge) -> {:ok, challenge}
      _ -> :error
    end
  end
end
