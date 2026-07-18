defmodule ChatWeb.ElectricLive.OriginSandboxLive.ApiClient do
  @moduledoc "API client for origin Electric ingest operations."

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.User
  alias Chat.TimeKeeper
  alias EnigmaPq

  def create_origin(owner, origin_name, moderation_mode, base_url) do
    origin_identity = User.generate_pq_identity(origin_name)
    origin_card = User.extract_pq_card(origin_identity)
    owner_cert = EnigmaPq.sign(origin_card.sign_pkey, owner.sign_skey)

    with {:ok, ch1, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <-
           ingest_user_card(ch1, origin_card, origin_identity.sign_skey, base_url),
         {:ok, ch2, log3} <- get_challenge(base_url),
         {:ok, origin_data, log4} <-
           ingest_origin(
             ch2,
             origin_card,
             owner,
             owner_cert,
             origin_name,
             moderation_mode,
             origin_identity.sign_skey,
             base_url
           ) do
      origin_data = Map.put(origin_data, :origin_crypt_skey, origin_identity.crypt_skey)
      {:ok, %{origin: origin_data, log_entries: [log1, log2, log3, log4]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def update_origin(origin, new_name, new_mode, base_url) do
    new_timestamp = origin.owner_timestamp + 1

    origin_struct = %Origin{
      origin_hash: origin.origin_hash,
      owner_hash: origin.owner_hash,
      owner_cert: origin.owner_cert,
      name: new_name,
      moderation_mode: String.to_existing_atom(new_mode),
      deleted_flag: false,
      owner_timestamp: new_timestamp
    }

    sign_b64 =
      origin_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(origin.origin_sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> OriginSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{"origin_hash" => origin.origin_hash},
          "changes" => %{
            "name" => new_name,
            "moderation_mode" => new_mode,
            "deleted_flag" => false,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "origins"}
        }
      ]
    }

    with {:ok, challenge_resp, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <-
           post_ingest(challenge_resp, payload, origin.origin_sign_skey, base_url) do
      updated =
        origin
        |> Map.put(:name, new_name)
        |> Map.put(:moderation_mode, new_mode)
        |> Map.put(:owner_timestamp, new_timestamp)

      {:ok, %{origin: updated, log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def delete_origin(origin, base_url) do
    new_timestamp = origin.owner_timestamp + 1

    origin_struct = %Origin{
      origin_hash: origin.origin_hash,
      owner_hash: origin.owner_hash,
      owner_cert: origin.owner_cert,
      name: origin.name,
      moderation_mode: String.to_existing_atom(origin.moderation_mode),
      deleted_flag: true,
      owner_timestamp: new_timestamp
    }

    sign_b64 =
      origin_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(origin.origin_sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> OriginSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{"origin_hash" => origin.origin_hash},
          "changes" => %{
            "name" => origin.name,
            "moderation_mode" => origin.moderation_mode,
            "deleted_flag" => true,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "origins"}
        }
      ]
    }

    with {:ok, challenge_resp, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <-
           post_ingest(challenge_resp, payload, origin.origin_sign_skey, base_url) do
      updated =
        origin
        |> Map.put(:deleted_flag, true)
        |> Map.put(:owner_timestamp, new_timestamp)

      {:ok, %{origin: updated, log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  # --- Private ---

  defp ingest_origin(
         challenge_resp,
         origin_card,
         owner,
         owner_cert,
         name,
         moderation_mode,
         origin_sign_skey,
         base_url
       ) do
    origin_struct = %Origin{
      origin_hash: origin_card.user_hash,
      owner_hash: owner.user_hash,
      owner_cert: owner_cert,
      name: name,
      moderation_mode: String.to_existing_atom(moderation_mode),
      deleted_flag: false,
      owner_timestamp: TimeKeeper.now_unix()
    }

    sign_b64 =
      origin_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(origin_sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> OriginSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "origin_hash" => origin_card.user_hash,
            "owner_hash" => owner.user_hash,
            "owner_cert" => encode_base64(owner_cert),
            "name" => name,
            "moderation_mode" => moderation_mode,
            "deleted_flag" => false,
            "owner_timestamp" => origin_struct.owner_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "origins"}
        }
      ]
    }

    case post_ingest(challenge_resp, payload, origin_sign_skey, base_url) do
      {:ok, _resp, log} ->
        origin_data = %{
          origin_hash: origin_card.user_hash,
          owner_hash: owner.user_hash,
          owner_cert: owner_cert,
          name: name,
          moderation_mode: moderation_mode,
          deleted_flag: false,
          owner_timestamp: origin_struct.owner_timestamp,
          origin_sign_skey: origin_sign_skey
        }

        {:ok, origin_data, log}

      error ->
        error
    end
  end

  defp ingest_user_card(challenge_resp, card, sign_skey, base_url) do
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
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }

    post_ingest(challenge_resp, payload, sign_skey, base_url)
  end

  defp get_challenge(base_url) do
    url = base_url <> "/electric/v1/challenge"
    req_headers = [{"accept", "application/json"}]
    timestamp = TimeKeeper.now()

    case Req.get(url, headers: req_headers) do
      {:ok, %{status: 200, body: body} = resp} ->
        {:ok, body, log_entry("GET", url, req_headers, "", resp, timestamp)}

      {:ok, %{status: status} = resp} ->
        {:error, "Challenge failed: #{status}",
         [log_entry("GET", url, req_headers, "", resp, timestamp)]}

      {:error, error} ->
        {:error, "Challenge failed: #{inspect(error)}",
         [log_entry("GET", url, req_headers, "", error, timestamp)]}
    end
  end

  defp post_ingest(challenge_resp, payload, sign_skey, base_url) do
    %{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp
    signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)

    payload_with_auth =
      Map.put(payload, "auth", %{
        "challenge_id" => challenge_id,
        "signature" => Base.encode64(signature, padding: false)
      })

    url = base_url <> "/electric/v1/ingest"
    req_headers = [{"accept", "application/json"}, {"content-type", "application/json"}]
    timestamp = TimeKeeper.now()
    body_json = Jason.encode!(payload_with_auth, pretty: true)

    case Req.post(url, json: payload_with_auth, headers: req_headers) do
      {:ok, %{status: status} = resp} when status in 200..299 ->
        {:ok, resp.body, log_entry("POST", url, req_headers, body_json, resp, timestamp)}

      {:ok, %{status: status} = resp} ->
        {:error, "Ingest failed: #{status}",
         [log_entry("POST", url, req_headers, body_json, resp, timestamp)]}

      {:error, error} ->
        {:error, "Ingest failed: #{inspect(error)}",
         [log_entry("POST", url, req_headers, body_json, error, timestamp)]}
    end
  end

  defp log_entry(method, url, req_headers, req_body, %{status: status, body: body, headers: headers}, ts) do
    resp_body = if is_map(body), do: Jason.encode!(body, pretty: true), else: inspect(body)

    %{
      timestamp: ts,
      method: method,
      url: url,
      request_headers: req_headers,
      request_body: req_body,
      response_status: status,
      response_headers: format_headers(headers),
      response_body: resp_body
    }
  end

  defp log_entry(method, url, req_headers, req_body, error, ts) do
    %{
      timestamp: ts,
      method: method,
      url: url,
      request_headers: req_headers,
      request_body: req_body,
      response_status: 0,
      response_headers: [],
      response_body: "Error: #{inspect(error)}"
    }
  end

  defp format_headers(%Req.Response{} = _resp), do: []

  defp format_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {k, Enum.join(v, ", ")} end)
  end

  defp format_headers(headers) when is_list(headers), do: headers
  defp format_headers(_), do: []

  defp encode_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)
end
