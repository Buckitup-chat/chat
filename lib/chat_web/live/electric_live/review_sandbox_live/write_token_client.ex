defmodule ChatWeb.ElectricLive.ReviewSandboxLive.WriteTokenClient do
  @moduledoc "HTTP client for write token bind operations in the review sandbox."

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.TimeKeeper

  def check_token(nonce, base_url, auth) do
    where = "nonce='#{nonce}'"

    case fetch_shape_gated(base_url, "review_write_tokens", where, auth) do
      {:ok, [row | _], logs} -> {:ok, parse_token(row), logs}
      {:ok, [], logs} -> {:error, "Token not found", logs}
      {:error, reason, logs} -> {:error, reason, logs}
    end
  end

  def bind_token(nonce, user_hash, sign_skey, base_url) do
    with {:ok, challenge_resp, ch_log} <- get_challenge(base_url) do
      %{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp
      signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)

      body = %{
        "nonce" => nonce,
        "user_hash" => user_hash,
        "auth" => %{
          "challenge_id" => challenge_id,
          "signature" => Base.encode64(signature, padding: false)
        }
      }

      body
      |> post_bind(base_url)
      |> prepend_log(ch_log)
    end
  end

  defp post_bind(body, base_url) do
    url = base_url <> "/r/api/token/bind"
    timestamp = TimeKeeper.now()
    headers = [{"accept", "application/json"}, {"content-type", "application/json"}]
    body_json = Jason.encode!(body, pretty: true)

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: resp_body} = resp} ->
        {:ok, resp_body, [log_entry("POST", url, headers, body_json, resp, timestamp)]}

      {:ok, %{status: _status} = resp} ->
        error_msg = if is_map(resp.body), do: resp.body["error"], else: "Bind failed"
        {:error, error_msg, [log_entry("POST", url, headers, body_json, resp, timestamp)]}

      {:error, error} ->
        {:error, "Bind failed: #{inspect(error)}",
         [log_entry("POST", url, headers, body_json, error, timestamp)]}
    end
  end

  defp prepend_log({tag, data, logs}, extra), do: {tag, data, [extra | logs]}

  def list_vouches(user_hash, base_url, auth) do
    where = "user_hash='#{user_hash}'"

    case fetch_shape_gated(base_url, "vouch_tokens", where, auth) do
      {:ok, rows, logs} -> {:ok, Enum.map(rows, &parse_vouch/1), logs}
      {:error, reason, logs} -> {:error, reason, logs}
    end
  end

  defp parse_token(row) do
    %{
      nonce: row["nonce"],
      origin_hash: row["origin_hash"],
      bot_hash: row["bot_hash"],
      user_hash: row["user_hash"],
      review_hash: row["review_hash"],
      origin_order_hash: row["origin_order_hash"],
      parent_nonce: row["parent_nonce"],
      deleted_flag: row["deleted_flag"] in [true, "true", "t"],
      owner_timestamp: parse_int(row["owner_timestamp"])
    }
  end

  defp parse_vouch(row) do
    %{
      voucher_hash: row["voucher_hash"],
      user_hash: row["user_hash"],
      resource_path: row["resource_path"],
      deleted_flag: row["deleted_flag"] in [true, "true", "t"],
      owner_timestamp: parse_int(row["owner_timestamp"])
    }
  end

  defp log_entry(method, url, req_headers, req_body, %{status: s, body: b, headers: h}, ts) do
    resp_body =
      if is_map(b) or is_list(b), do: Jason.encode!(b, pretty: true), else: inspect(b)

    %{
      timestamp: ts,
      method: method,
      url: url,
      request_headers: req_headers,
      request_body: req_body,
      response_status: s,
      response_headers: format_headers(h),
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

  defp format_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {k, Enum.join(v, ", ")} end)
  end

  defp format_headers(headers) when is_list(headers), do: headers
  defp format_headers(_), do: []

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
  defp parse_int(_), do: 0
end
