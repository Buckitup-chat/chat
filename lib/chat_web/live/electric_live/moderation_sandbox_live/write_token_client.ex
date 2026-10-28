defmodule ChatWeb.ElectricLive.ModerationSandboxLive.WriteTokenClient do
  @moduledoc "HTTP calls for review write token operations in the origin sandbox."

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.TimeKeeper

  def create_token(bot_hash, origin_order_hash, auth_token, base_url) do
    url = base_url <> "/r/api/token/create"
    timestamp = TimeKeeper.now()

    headers =
      [{"accept", "application/json"}, {"content-type", "application/json"}]
      |> then(fn h ->
        case auth_token do
          nil -> h
          token -> [{"authorization", "Bearer #{token}"} | h]
        end
      end)

    body =
      %{"bot_hash" => bot_hash}
      |> then(fn b ->
        case origin_order_hash do
          nil -> b
          "" -> b
          hash -> Map.put(b, "origin_order_hash", hash)
        end
      end)

    body_json = Jason.encode!(body, pretty: true)

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: resp_body} = resp} ->
        {:ok, resp_body, [log_entry("POST", url, headers, body_json, resp, timestamp)]}

      {:ok, %{status: _status} = resp} ->
        error_msg = if is_map(resp.body), do: resp.body["error"], else: "Token create failed"
        {:error, error_msg, [log_entry("POST", url, headers, body_json, resp, timestamp)]}

      {:error, error} ->
        {:error, "Token create failed: #{inspect(error)}",
         [log_entry("POST", url, headers, body_json, error, timestamp)]}
    end
  end

  def list_tokens(origin_hash, base_url, auth) do
    case fetch_shape_gated(base_url, "review_write_tokens", "origin_hash='#{origin_hash}'", auth) do
      {:ok, rows, logs} -> {:ok, Enum.map(rows, &parse_token_row/1), logs}
      {:error, _reason, _logs} = error -> error
    end
  end

  defp parse_token_row(row) do
    %{
      nonce: row["nonce"],
      origin_hash: row["origin_hash"],
      origin_order_hash: row["origin_order_hash"],
      bot_hash: row["bot_hash"],
      user_hash: row["user_hash"],
      review_hash: row["review_hash"],
      parent_nonce: row["parent_nonce"],
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
