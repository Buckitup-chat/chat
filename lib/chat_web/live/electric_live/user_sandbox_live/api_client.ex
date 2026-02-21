defmodule ChatWeb.ElectricLive.UserSandboxLive.ApiClient do
  @moduledoc """
  API client for Electric ingest operations with request/response logging.
  """

  alias Chat.Data.User

  @doc """
  Creates a new user via the Electric API.

  Returns:
  - `{:ok, %{user: user_map, log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def create_user(name, base_url) do
    # Generate PQ identity and extract card
    identity = User.generate_pq_identity(name)
    card = User.extract_pq_card(identity)

    # Step 1: Get challenge
    challenge_url = base_url <> "/electric/v1/challenge"

    with {:ok, challenge_resp, challenge_log} <- get_challenge(challenge_url),
         {:ok, _ingest_resp, ingest_log} <-
           ingest_user_card(challenge_resp, card, identity.sign_skey, base_url) do
      user_data = %{
        name: card.name,
        user_hash: card.user_hash,
        user_hash_hex: Base.encode16(card.user_hash, case: :lower),
        sign_skey: identity.sign_skey,
        sign_pkey: card.sign_pkey
      }

      {:ok, %{user: user_data, log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} ->
        {:error, %{reason: reason, log_entries: log_entries}}
    end
  end

  @doc """
  Updates a user's name via the Electric API.

  Returns:
  - `{:ok, %{txid: txid, log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def update_user_name(user_hash, sign_skey, new_name, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "modified" => %{
            "user_hash" => encode_hex(user_hash),
            "name" => new_name
          },
          "syncMetadata" => %{
            "relation" => "user_cards"
          }
        }
      ]
    }

    with {:ok, challenge_resp, challenge_log} <- get_challenge(challenge_url),
         {:ok, ingest_resp, ingest_log} <-
           post_ingest(challenge_resp, payload, sign_skey, base_url) do
      {:ok, %{txid: ingest_resp["txid"], log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} ->
        {:error, %{reason: reason, log_entries: log_entries}}
    end
  end

  @doc """
  Deletes a user via the Electric API.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def delete_user(user_hash, sign_skey, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"

    payload = %{
      "mutations" => [
        %{
          "type" => "delete",
          "modified" => %{
            "user_hash" => encode_hex(user_hash)
          },
          "syncMetadata" => %{
            "relation" => "user_cards"
          }
        }
      ]
    }

    with {:ok, challenge_resp, challenge_log} <- get_challenge(challenge_url),
         {:ok, _ingest_resp, ingest_log} <-
           post_ingest(challenge_resp, payload, sign_skey, base_url) do
      {:ok, %{log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} ->
        {:error, %{reason: reason, log_entries: log_entries}}
    end
  end

  @doc """
  Creates a storage entry via the Electric API.

  `value` should be raw binary data. It will be encoded as `\\x<hex>` in the JSON payload.

  Returns:
  - `{:ok, %{uuid: uuid, log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def create_storage(user_hash, sign_skey, uuid, value_binary, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => encode_hex(user_hash),
            "uuid" => uuid,
            "value" => encode_hex(value_binary)
          },
          "syncMetadata" => %{
            "relation" => "user_storage"
          }
        }
      ]
    }

    with {:ok, challenge_resp, challenge_log} <- get_challenge(challenge_url),
         {:ok, ingest_resp, ingest_log} <-
           post_ingest(challenge_resp, payload, sign_skey, base_url) do
      {:ok,
       %{uuid: uuid, txid: ingest_resp["txid"], log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} ->
        {:error, %{reason: reason, log_entries: log_entries}}
    end
  end

  @doc """
  Updates a storage entry via the Electric API.

  `value_binary` should be raw binary data. It will be encoded as `\\x<hex>` in the JSON payload.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def update_storage(user_hash, sign_skey, uuid, value_binary, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "modified" => %{
            "user_hash" => encode_hex(user_hash),
            "uuid" => uuid,
            "value" => encode_hex(value_binary)
          },
          "syncMetadata" => %{
            "relation" => "user_storage"
          }
        }
      ]
    }

    with {:ok, challenge_resp, challenge_log} <- get_challenge(challenge_url),
         {:ok, ingest_resp, ingest_log} <-
           post_ingest(challenge_resp, payload, sign_skey, base_url) do
      {:ok, %{txid: ingest_resp["txid"], log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} ->
        {:error, %{reason: reason, log_entries: log_entries}}
    end
  end

  @doc """
  Deletes a storage entry via the Electric API.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def delete_storage(user_hash, sign_skey, uuid, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"

    payload = %{
      "mutations" => [
        %{
          "type" => "delete",
          "modified" => %{
            "user_hash" => encode_hex(user_hash),
            "uuid" => uuid
          },
          "syncMetadata" => %{
            "relation" => "user_storage"
          }
        }
      ]
    }

    with {:ok, challenge_resp, challenge_log} <- get_challenge(challenge_url),
         {:ok, _ingest_resp, ingest_log} <-
           post_ingest(challenge_resp, payload, sign_skey, base_url) do
      {:ok, %{log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} ->
        {:error, %{reason: reason, log_entries: log_entries}}
    end
  end

  # Private helpers

  defp get_challenge(challenge_url) do
    timestamp = DateTime.utc_now()

    case Req.get(challenge_url, headers: [{"accept", "application/json"}]) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        log_entry = %{
          timestamp: timestamp,
          method: "GET",
          url: challenge_url,
          request_headers: [{"accept", "application/json"}],
          request_body: "",
          response_status: 200,
          response_headers: headers,
          response_body: Jason.encode!(body, pretty: true)
        }

        {:ok, body, log_entry}

      {:ok, %{status: status, body: body, headers: headers}} ->
        log_entry = %{
          timestamp: timestamp,
          method: "GET",
          url: challenge_url,
          request_headers: [{"accept", "application/json"}],
          request_body: "",
          response_status: status,
          response_headers: headers,
          response_body: inspect(body)
        }

        {:error, "Challenge request failed with status #{status}", [log_entry]}

      {:error, error} ->
        log_entry = %{
          timestamp: timestamp,
          method: "GET",
          url: challenge_url,
          request_headers: [{"accept", "application/json"}],
          request_body: "",
          response_status: 0,
          response_headers: [],
          response_body: "Error: #{inspect(error)}"
        }

        {:error, "Challenge request failed: #{inspect(error)}", [log_entry]}
    end
  end

  defp ingest_user_card(challenge_resp, card, sign_skey, base_url) do
    %{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp

    # Sign the challenge
    signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)
    signature_b64 = Base.encode64(signature, padding: false)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => encode_hex(card.user_hash),
            "sign_pkey" => encode_hex(card.sign_pkey),
            "contact_pkey" => encode_hex(card.contact_pkey),
            "contact_cert" => encode_hex(card.contact_cert),
            "crypt_pkey" => encode_hex(card.crypt_pkey),
            "crypt_cert" => encode_hex(card.crypt_cert),
            "name" => card.name
          },
          "syncMetadata" => %{
            "relation" => "user_cards"
          }
        }
      ],
      "auth" => %{
        "challenge_id" => challenge_id,
        "signature" => signature_b64
      }
    }

    post_ingest(challenge_resp, payload, sign_skey, base_url)
  end

  defp post_ingest(challenge_resp, payload, sign_skey, base_url) do
    %{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp

    # Sign the challenge
    signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)
    signature_b64 = Base.encode64(signature, padding: false)

    # Add auth to payload
    payload_with_auth =
      Map.put(payload, "auth", %{
        "challenge_id" => challenge_id,
        "signature" => signature_b64
      })

    ingest_url = base_url <> "/electric/v1/ingest"
    timestamp = DateTime.utc_now()

    headers = [
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    case Req.post(ingest_url, json: payload_with_auth, headers: headers) do
      {:ok, %{status: status, body: body, headers: resp_headers}} when status in 200..299 ->
        log_entry = %{
          timestamp: timestamp,
          method: "POST",
          url: ingest_url,
          request_headers: headers,
          request_body: Jason.encode!(payload_with_auth, pretty: true),
          response_status: status,
          response_headers: resp_headers,
          response_body: Jason.encode!(body, pretty: true)
        }

        {:ok, body, log_entry}

      {:ok, %{status: status, body: body, headers: resp_headers}} ->
        log_entry = %{
          timestamp: timestamp,
          method: "POST",
          url: ingest_url,
          request_headers: headers,
          request_body: Jason.encode!(payload_with_auth, pretty: true),
          response_status: status,
          response_headers: resp_headers,
          response_body: inspect(body)
        }

        {:error, "Ingest request failed with status #{status}", [log_entry]}

      {:error, error} ->
        log_entry = %{
          timestamp: timestamp,
          method: "POST",
          url: ingest_url,
          request_headers: headers,
          request_body: Jason.encode!(payload_with_auth, pretty: true),
          response_status: 0,
          response_headers: [],
          response_body: "Error: #{inspect(error)}"
        }

        {:error, "Ingest request failed: #{inspect(error)}", [log_entry]}
    end
  end

  defp encode_hex(bin) when is_binary(bin) do
    "\\x" <> Base.encode16(bin, case: :lower)
  end
end
