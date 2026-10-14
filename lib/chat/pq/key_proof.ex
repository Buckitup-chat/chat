defmodule Chat.Pq.KeyProof do
  @moduledoc """
  Proof of possession over a one-time challenge for a card stored on this
  device: shared by read sessions (`Chat.Pq.ReadGate`) and the owner claim
  (`ChatWeb.OwnerClaimController`).
  """

  alias Chat.Challenge
  alias Chat.Data.User, as: UserData

  @doc """
  Proves that `user_hash` holds the key of its stored, undeleted card by its
  signature over a fresh challenge. Returns `{:ok, card}` or `{:error, reason}`
  where reason is one of `:invalid_challenge`, `:unknown_user`, `:invalid_signature`.
  """
  def prove(user_hash, challenge_id, signature_b64) do
    with {:ok, challenge} <- consume_challenge(challenge_id),
         {:ok, card} <- fetch_card(user_hash),
         :ok <- verify_signature(challenge, signature_b64, card.sign_pkey) do
      {:ok, card}
    end
  end

  defp consume_challenge(challenge_id) when is_binary(challenge_id) do
    case Challenge.get(challenge_id) do
      challenge when is_binary(challenge) -> {:ok, challenge}
      _ -> {:error, :invalid_challenge}
    end
  end

  defp consume_challenge(_), do: {:error, :invalid_challenge}

  defp fetch_card(user_hash) when is_binary(user_hash) do
    case UserData.get_card(user_hash) do
      %{deleted_flag: false} = card -> {:ok, card}
      _ -> {:error, :unknown_user}
    end
  rescue
    Ecto.Query.CastError -> {:error, :unknown_user}
  end

  defp fetch_card(_), do: {:error, :unknown_user}

  defp verify_signature(challenge, signature_b64, sign_pkey) when is_binary(signature_b64) do
    with {:ok, signature} <- Base.decode64(signature_b64, padding: false),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  rescue
    ErlangError -> {:error, :invalid_signature}
  end

  defp verify_signature(_, _, _), do: {:error, :invalid_signature}
end
