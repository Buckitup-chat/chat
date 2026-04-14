defmodule ChatWeb.ElectricLive.UserSandboxLive.ApiClient do
  @moduledoc """
  API client for Electric ingest operations with request/response logging.
  """

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Types.UserStorageSignHash
  alias Chat.Data.User
  alias Chat.Db
  alias Chat.TimeKeeper

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
      user_data =
        card
        |> Map.from_struct()
        # Remove "u_" prefix for display
        |> Map.put(:user_hash_hex, String.slice(card.user_hash, 2..-1//1))
        |> Map.put(:sign_skey, identity.sign_skey)

      {:ok, %{user: user_data, log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} ->
        {:error, %{reason: reason, log_entries: log_entries}}
    end
  end

  @doc """
  Updates a user's name via the Electric API.

  `existing_card` must be the full UserCard struct with all fields.

  Returns:
  - `{:ok, %{txid: txid, log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def update_user_name(existing_card, sign_skey, new_name, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"

    new_timestamp = existing_card.owner_timestamp + 1

    updated_card_struct =
      struct(UserCard, Map.put(existing_card, :name, new_name))
      |> Map.put(:owner_timestamp, new_timestamp)

    sign_b64 =
      updated_card_struct
      |> Integrity.signature_payload()
      |> then(&:crypto.sign(:mldsa87, :none, &1, sign_skey))

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "user_hash" => existing_card.user_hash
          },
          "changes" => %{
            "name" => new_name,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64)
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
  Soft-deletes a user via the Electric API by setting deleted_flag=true.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def delete_user(user_hash, sign_skey, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"

    # Fetch current user card to get current timestamp
    repo = Db.repo()
    existing_card = repo.get(UserCard, user_hash)

    if is_nil(existing_card) do
      {:error, %{reason: "User not found", log_entries: []}}
    else
      delete_user_with_card(existing_card, user_hash, sign_skey, base_url, challenge_url)
    end
  end

  defp delete_user_with_card(existing_card, user_hash, sign_skey, base_url, challenge_url) do
    new_timestamp = existing_card.owner_timestamp + 1

    # Create updated card with deleted_flag=true for signing
    updated_card_struct =
      existing_card
      |> Map.put(:deleted_flag, true)
      |> Map.put(:owner_timestamp, new_timestamp)

    sign_b64 =
      updated_card_struct
      |> Integrity.signature_payload()
      |> then(&:crypto.sign(:mldsa87, :none, &1, sign_skey))

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "user_hash" => user_hash
          },
          "changes" => %{
            "deleted_flag" => true,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64)
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

  `value` should be raw binary data. It will be encoded as base64 in the JSON payload.

  Returns:
  - `{:ok, %{uuid: uuid, log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def create_storage(user_hash, sign_skey, uuid, value_binary, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"
    owner_timestamp = System.system_time(:second)

    # Create storage struct for signing
    storage_attrs = %{
      user_hash: user_hash,
      uuid: uuid,
      value_b64: value_binary,
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: owner_timestamp
    }

    storage_struct = struct(UserStorage, storage_attrs)
    sign_payload = Integrity.signature_payload(storage_struct)
    sign_b64 = :crypto.sign(:mldsa87, :none, sign_payload, sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> UserStorageSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => user_hash,
            "uuid" => uuid,
            "value_b64" => encode_base64(value_binary),
            "deleted_flag" => false,
            "parent_sign_hash" => nil,
            "owner_timestamp" => owner_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
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
      {:ok, %{uuid: uuid, txid: ingest_resp["txid"], log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} ->
        {:error, %{reason: reason, log_entries: log_entries}}
    end
  end

  @doc """
  Updates a storage entry via the Electric API.

  `value_binary` should be raw binary data. It will be encoded as base64 in the JSON payload.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def update_storage(user_hash, sign_skey, uuid, value_binary, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"

    # Fetch existing storage to get current timestamp and sign_hash for parent reference
    repo = Db.repo()
    existing = repo.get_by(UserStorage, user_hash: user_hash, uuid: uuid)

    if is_nil(existing) do
      {:error, %{reason: "Storage entry not found", log_entries: []}}
    else
      owner_timestamp = existing.owner_timestamp + 1
      parent_sign_hash = existing.sign_hash

      # Create storage struct for signing
      storage_attrs = %{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: value_binary,
        deleted_flag: false,
        parent_sign_hash: parent_sign_hash,
        owner_timestamp: owner_timestamp
      }

      storage_struct = struct(UserStorage, storage_attrs)
      sign_payload = Integrity.signature_payload(storage_struct)
      sign_b64 = :crypto.sign(:mldsa87, :none, sign_payload, sign_skey)

      sign_hash =
        sign_b64
        |> EnigmaPq.hash()
        |> UserStorageSignHash.from_binary()

      payload = %{
        "mutations" => [
          %{
            "type" => "update",
            "original" => %{
              "user_hash" => user_hash,
              "uuid" => uuid
            },
            "changes" => %{
              "value_b64" => encode_base64(value_binary),
              "deleted_flag" => false,
              "parent_sign_hash" => parent_sign_hash,
              "owner_timestamp" => owner_timestamp,
              "sign_b64" => encode_base64(sign_b64),
              "sign_hash" => sign_hash
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
  end

  @doc """
  Soft-deletes a storage entry via the Electric API by setting deleted_flag=true.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def delete_storage(user_hash, sign_skey, uuid, base_url) do
    challenge_url = base_url <> "/electric/v1/challenge"

    # Fetch existing storage to get current timestamp and sign_hash for parent reference
    repo = Db.repo()
    existing = repo.get_by(UserStorage, user_hash: user_hash, uuid: uuid)

    if is_nil(existing) do
      {:error, %{reason: "Storage entry not found", log_entries: []}}
    else
      owner_timestamp = existing.owner_timestamp + 1
      parent_sign_hash = existing.sign_hash

      # Create storage struct for signing with deleted_flag=true
      storage_attrs = %{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: existing.value_b64,
        deleted_flag: true,
        parent_sign_hash: parent_sign_hash,
        owner_timestamp: owner_timestamp
      }

      storage_struct = struct(UserStorage, storage_attrs)
      sign_payload = Integrity.signature_payload(storage_struct)
      sign_b64 = :crypto.sign(:mldsa87, :none, sign_payload, sign_skey)

      sign_hash =
        sign_b64
        |> EnigmaPq.hash()
        |> UserStorageSignHash.from_binary()

      payload = %{
        "mutations" => [
          %{
            "type" => "update",
            "original" => %{
              "user_hash" => user_hash,
              "uuid" => uuid
            },
            "changes" => %{
              "deleted_flag" => true,
              "parent_sign_hash" => parent_sign_hash,
              "owner_timestamp" => owner_timestamp,
              "sign_b64" => encode_base64(sign_b64),
              "sign_hash" => sign_hash
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
  end

  # Private helpers

  defp get_challenge(challenge_url) do
    timestamp = TimeKeeper.now()

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
            "user_hash" => card.user_hash,
            "sign_pkey" => encode_base64(card.sign_pkey),
            "contact_pkey" => encode_base64(card.contact_pkey),
            "contact_cert" => encode_base64(card.contact_cert),
            "crypt_pkey" => encode_base64(card.crypt_pkey),
            "crypt_cert" => encode_base64(card.crypt_cert),
            "name" => card.name,
            "deleted_flag" => card.deleted_flag,
            "owner_timestamp" => card.owner_timestamp,
            "sign_b64" => encode_base64(card.sign_b64)
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
    timestamp = TimeKeeper.now()

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

  defp encode_base64(bin) when is_binary(bin) do
    Base.encode64(bin, padding: false)
  end
end
