defmodule ChatWeb.ElectricLive.ReviewSandboxLive.ApiClient do
  @moduledoc "API client for review Electric ingest operations."

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.TimeKeeper
  alias EnigmaPq

  def submit_review(author, origin_hash, content, base_url) do
    review_hash = :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    review_password = :crypto.strong_rand_bytes(32)
    content_b64 = EnigmaPq.aes_gcm_encrypt(content, review_password)
    timestamp = TimeKeeper.now_unix()

    review_struct = %Review{
      review_hash: review_hash,
      origin_hash: origin_hash,
      author_hash: author.user_hash,
      content_b64: content_b64,
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: timestamp
    }

    sign_b64 =
      review_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(author.sign_skey)

    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "review_hash" => review_hash,
            "origin_hash" => origin_hash,
            "author_hash" => author.user_hash,
            "content_b64" => encode_base64(content_b64),
            "deleted_flag" => false,
            "owner_timestamp" => timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "review"}
        }
      ]
    }

    with {:ok, ch, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <- post_ingest(ch, payload, author.sign_skey, base_url) do
      review_data = %{
        review_hash: review_hash,
        origin_hash: origin_hash,
        review_password: review_password,
        content: content,
        owner_timestamp: timestamp
      }

      {:ok, %{review: review_data, log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def submit_password_candidate(author, review, origin_hash, base_url) do
    timestamp = TimeKeeper.now_unix()

    pwd_struct = %ReviewPublicPassword{
      review_hash: review.review_hash,
      origin_hash: origin_hash,
      password_b64: review.review_password,
      author_hash: author.user_hash,
      deleted_flag: false,
      owner_timestamp: timestamp
    }

    sign_b64 =
      pwd_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(author.sign_skey)

    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "review_hash" => review.review_hash,
            "sign_hash" => sign_hash,
            "origin_hash" => origin_hash,
            "password_b64" => encode_base64(review.review_password),
            "author_hash" => author.user_hash,
            "deleted_flag" => false,
            "owner_timestamp" => timestamp,
            "sign_b64" => encode_base64(sign_b64)
          },
          "syncMetadata" => %{"relation" => "review_public_passwords"}
        }
      ]
    }

    with {:ok, ch, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <- post_ingest(ch, payload, author.sign_skey, base_url) do
      {:ok, %{sign_hash: sign_hash, log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def submit_review_list_entry(author, review, review_password_sign_hash, base_url) do
    timestamp = TimeKeeper.now_unix()
    encrypted_pwd = EnigmaPq.aes_gcm_encrypt(review.review_password, author.review_list_password)

    rl_struct = %ReviewList{
      user_hash: author.user_hash,
      review_hash: review.review_hash,
      password_b64: encrypted_pwd,
      review_password_sign_hash: review_password_sign_hash,
      post_right_sign_hash: nil,
      revoke_right_sign_hash: nil,
      deleted_flag: false,
      owner_timestamp: timestamp
    }

    sign_b64 =
      rl_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(author.sign_skey)

    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewListSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => author.user_hash,
            "review_hash" => review.review_hash,
            "password_b64" => encode_base64(encrypted_pwd),
            "review_password_sign_hash" => review_password_sign_hash,
            "deleted_flag" => false,
            "owner_timestamp" => timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "review_list"}
        }
      ]
    }

    with {:ok, ch, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <- post_ingest(ch, payload, author.sign_skey, base_url) do
      {:ok, %{log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  # --- Private ---

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

  defp log_entry(method, url, req_headers, req_body, response_or_error, ts) do
    {status, resp_headers, resp_body} =
      case response_or_error do
        %{status: status, body: body, headers: headers} ->
          formatted = if is_map(body), do: Jason.encode!(body, pretty: true), else: inspect(body)
          {status, format_headers(headers), formatted}

        error ->
          {0, [], "Error: #{inspect(error)}"}
      end

    %{
      timestamp: ts,
      method: method,
      url: url,
      request_headers: req_headers,
      request_body: req_body,
      response_status: status,
      response_headers: resp_headers,
      response_body: resp_body
    }
  end

  defp format_headers(%Req.Response{}), do: []

  defp format_headers(headers) when is_map(headers),
    do: Enum.map(headers, fn {k, v} -> {k, Enum.join(v, ", ")} end)

  defp format_headers(headers) when is_list(headers), do: headers
  defp format_headers(_), do: []

  defp encode_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)
end
