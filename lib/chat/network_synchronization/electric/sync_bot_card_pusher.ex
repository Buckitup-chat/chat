defmodule Chat.NetworkSynchronization.Electric.SyncBotCardPusher do
  @moduledoc """
  Pushes this device's SyncBot user_card to a peer via its `/ingest` endpoint.

  Called during peer connection setup so the peer knows our SyncBot identity
  and its admin can approve it for read/write access. The push is idempotent —
  user_card upsert on the peer keeps the newer owner_timestamp.
  """

  alias Chat.Data.User
  alias Chat.DeviceId
  alias Chat.Pq.ServerIdentity

  @timeout 10_000

  @doc """
  Pushes the local SyncBot's user_card to `peer_url`.

  Returns `:ok` on success (200 or 409/exists) or `{:error, reason}`.
  """
  def push(peer_url) do
    identity = server_identity_with_name()
    card = User.extract_pq_card(identity)

    with {:ok, challenge_id, challenge} <- fetch_challenge(peer_url) do
      "#{peer_url}/electric/v1/ingest"
      |> Req.post(
        json: ingest_payload(card, challenge_id, sign(challenge, identity)),
        receive_timeout: @timeout,
        retry: false
      )
      |> handle_response()
    end
  end

  defp server_identity_with_name do
    ServerIdentity.get()
    |> Map.put(:name, "SyncBot_#{DeviceId.id()}")
  end

  defp ingest_payload(card, challenge_id, signature) do
    %{
      "auth" => %{
        "challenge_id" => challenge_id,
        "signature" => signature
      },
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => card_to_modified(card),
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }
  end

  defp card_to_modified(card) do
    %{
      "user_hash" => card.user_hash,
      "sign_pkey" => to_b64(card.sign_pkey),
      "contact_pkey" => to_b64(card.contact_pkey),
      "contact_cert" => to_b64(card.contact_cert),
      "crypt_pkey" => to_b64(card.crypt_pkey),
      "crypt_cert" => to_b64(card.crypt_cert),
      "name" => card.name,
      "deleted_flag" => card.deleted_flag,
      "owner_timestamp" => card.owner_timestamp,
      "sign_b64" => to_b64(card.sign_b64)
    }
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

  defp handle_response(result) do
    case result do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: 409}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, _} = error -> error
    end
  end

  defp sign(challenge, identity) do
    challenge
    |> EnigmaPq.sign(identity.sign_skey)
    |> to_b64()
  end

  defp to_b64(bin), do: Base.encode64(bin, padding: false)
end
