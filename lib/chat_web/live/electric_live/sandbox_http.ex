defmodule ChatWeb.ElectricLive.SandboxHttp do
  @moduledoc """
  Shared HTTP client for Electric sandbox operations.

  Sandboxes are reference implementations for external clients — all reads and
  writes go through raw HTTP, never through `Electric.Client`, `ShapeReader`,
  `Ecto`, or `Db.repo()`.
  """

  alias Chat.Data.Integrity
  alias Chat.TimeKeeper

  # --- Shape reads ---

  def fetch_shape(base_url, table), do: fetch_shape(base_url, table, nil)

  def fetch_shape(base_url, table, nil) do
    "#{base_url}/electric/v1/shapes?table=#{table}&offset=-1"
    |> do_fetch_shape()
  end

  def fetch_shape(base_url, table, where) do
    "#{base_url}/electric/v1/shapes?table=#{table}&offset=-1&where=#{URI.encode(where)}"
    |> do_fetch_shape()
  end

  # --- Writes ---

  def get_challenge(base_url) do
    url = base_url <> "/electric/v1/challenge"
    timestamp = TimeKeeper.now()
    headers = [{"accept", "application/json"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body} = resp} ->
        {:ok, body, log_entry("GET", url, headers, "", resp, timestamp)}

      {:ok, %{status: status} = resp} ->
        {:error, "Challenge failed: #{status}",
         [log_entry("GET", url, headers, "", resp, timestamp)]}

      {:error, error} ->
        {:error, "Challenge failed: #{inspect(error)}",
         [log_entry("GET", url, headers, "", error, timestamp)]}
    end
  end

  def post_ingest(challenge_resp, payload, sign_skey, base_url) do
    %{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp
    signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)

    payload_with_auth =
      Map.put(payload, "auth", %{
        "challenge_id" => challenge_id,
        "signature" => Base.encode64(signature, padding: false)
      })

    url = base_url <> "/electric/v1/ingest"
    timestamp = TimeKeeper.now()
    headers = [{"accept", "application/json"}, {"content-type", "application/json"}]
    body_json = Jason.encode!(payload_with_auth, pretty: true)

    case Req.post(url, json: payload_with_auth, headers: headers) do
      {:ok, %{status: status} = resp} when status in 200..299 ->
        {:ok, resp.body, log_entry("POST", url, headers, body_json, resp, timestamp)}

      {:ok, %{status: status} = resp} ->
        {:error, "Ingest failed: #{status}",
         [log_entry("POST", url, headers, body_json, resp, timestamp)]}

      {:error, error} ->
        {:error, "Ingest failed: #{inspect(error)}",
         [log_entry("POST", url, headers, body_json, error, timestamp)]}
    end
  end

  def ingest(payload, sign_skey, base_url) do
    case get_challenge(base_url) do
      {:ok, challenge_resp, log1} ->
        case post_ingest(challenge_resp, payload, sign_skey, base_url) do
          {:ok, body, log2} -> {:ok, body, [log1, log2]}
          {:error, reason, logs} -> {:error, reason, [log1 | logs]}
        end

      {:error, _reason, _logs} = error ->
        error
    end
  end

  # --- Read sessions ---

  @doc """
  Opens a read session for `shape` on the peer. Returns a Bearer token.

  Protocol: `GET /challenge` → sign → `POST /read_session`.
  """
  def open_read_session(base_url, shape, user_hash, sign_skey) do
    with {:ok, challenge_resp, challenge_log} <- get_challenge(base_url) do
      %{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp
      signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)

      url = base_url <> "/electric/v1/read_session"
      timestamp = TimeKeeper.now()
      headers = [{"accept", "application/json"}, {"content-type", "application/json"}]

      body = %{
        "user_hash" => user_hash,
        "shape" => shape,
        "challenge_id" => challenge_id,
        "signature" => Base.encode64(signature, padding: false)
      }

      body_json = Jason.encode!(body, pretty: true)

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: %{"token" => token, "expires_in" => expires_in}} = resp} ->
          {:ok, token, expires_in,
           [challenge_log, log_entry("POST", url, headers, body_json, resp, timestamp)]}

        {:ok, %{status: _status} = resp} ->
          error_msg = if is_map(resp.body), do: resp.body["error"], else: nil
          {:error, error_msg || "Read session failed: #{resp.status}",
           [challenge_log, log_entry("POST", url, headers, body_json, resp, timestamp)]}

        {:error, error} ->
          {:error, "Read session failed: #{inspect(error)}",
           [challenge_log, log_entry("POST", url, headers, body_json, error, timestamp)]}
      end
    end
  end

  # --- Gated shape reads ---

  @doc """
  Like `fetch_shape/2,3` but opens a read session on `401 read_session_required`.

  `auth` is `%{user_hash: _, sign_skey: _}`.
  Returns `{:ok, rows, logs}` or `{:error, reason, logs}` where logs is always a list.
  """
  def fetch_shape_gated(base_url, table, auth), do: fetch_shape_gated(base_url, table, nil, auth)

  def fetch_shape_gated(base_url, table, where, %{user_hash: _, sign_skey: _} = auth) do
    url = shape_url(base_url, table, where)
    timestamp = TimeKeeper.now()
    headers = [{"accept", "application/json"}]

    case fetch_pages(url, headers, %{}) do
      {:ok, rows} ->
        {:ok, rows, [shape_log(url, headers, rows, timestamp)]}

      {:error, {401, %{"error" => "read_session_required", "shape" => shape}, rh}} ->
        gate_log =
          build_log(
            "GET",
            url,
            headers,
            "",
            401,
            format_headers(rh),
            Jason.encode!(%{"error" => "read_session_required", "shape" => shape}),
            timestamp
          )

        retry_with_session(base_url, url, shape, auth, [gate_log])

      {:error, {status, body, rh}} ->
        {:error, "Shape request failed (#{status})",
         [build_log("GET", url, headers, "", status, format_headers(rh), inspect(body), timestamp)]}

      {:error, reason} ->
        {:error, "Shape request failed: #{inspect(reason)}",
         [build_log("GET", url, headers, "", 0, [], inspect(reason), timestamp)]}
    end
  end

  defp retry_with_session(base_url, url, shape, auth, logs) do
    case open_read_session(base_url, shape, auth.user_hash, auth.sign_skey) do
      {:ok, token, _expires_in, session_logs} ->
        retry_ts = TimeKeeper.now()
        retry_headers = [{"accept", "application/json"}, {"authorization", "Bearer #{token}"}]

        case fetch_pages(url, retry_headers, %{}) do
          {:ok, rows} ->
            {:ok, rows, logs ++ session_logs ++ [shape_log(url, retry_headers, rows, retry_ts)]}

          {:error, {status, body, rh}} ->
            {:error, "Shape request failed (#{status})",
             logs ++
               session_logs ++
               [build_log("GET", url, retry_headers, "", status, format_headers(rh), inspect(body), retry_ts)]}

          {:error, reason} ->
            {:error, "Shape request failed: #{inspect(reason)}",
             logs ++
               session_logs ++
               [build_log("GET", url, retry_headers, "", 0, [], inspect(reason), retry_ts)]}
        end

      {:error, reason, session_logs} ->
        {:error, reason, logs ++ session_logs}
    end
  end

  defp shape_url(base_url, table, nil),
    do: "#{base_url}/electric/v1/shapes?table=#{table}&offset=-1"

  defp shape_url(base_url, table, where),
    do: "#{base_url}/electric/v1/shapes?table=#{table}&offset=-1&where=#{URI.encode(where)}"

  defp shape_log(url, headers, rows, timestamp) do
    build_log("GET", url, headers, "", 200, [], Jason.encode!(rows, pretty: true), timestamp)
  end

  # --- Utilities ---

  def encode_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)

  def sign_struct(struct, sign_skey, hash_module) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> hash_module.from_binary()
    {sign_b64, sign_hash}
  end

  # --- Private ---

  defp do_fetch_shape(url) do
    timestamp = TimeKeeper.now()
    headers = [{"accept", "application/json"}]

    case fetch_pages(url, headers, %{}) do
      {:ok, rows} ->
        {:ok, rows,
         build_log("GET", url, headers, "", 200, [], Jason.encode!(rows, pretty: true), timestamp)}

      {:error, {status, body, rh}} ->
        {:error, "Shape request failed (#{status})",
         build_log(
           "GET",
           url,
           headers,
           "",
           status,
           format_headers(rh),
           inspect(body),
           timestamp
         )}

      {:error, reason} ->
        {:error, "Shape request failed: #{inspect(reason)}",
         build_log("GET", url, headers, "", 0, [], inspect(reason), timestamp)}
    end
  end

  defp fetch_pages(url, headers, acc) do
    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body, headers: rh}} ->
        rows = fold_operations(acc, body)

        if up_to_date?(body) do
          {:ok, Map.values(rows)}
        else
          fetch_pages(next_page_url(url, rh), headers, rows)
        end

      {:ok, %{status: 204}} ->
        {:ok, Map.values(acc)}

      {:ok, %{status: s, body: b, headers: rh}} ->
        {:error, {s, b, rh}}

      {:error, e} ->
        {:error, e}
    end
  end

  defp up_to_date?(body) when is_list(body) do
    Enum.any?(body, &match?(%{"headers" => %{"control" => "up-to-date"}}, &1))
  end

  defp up_to_date?(_), do: true

  defp next_page_url(url, resp_headers) do
    [offset | _] = resp_headers["electric-offset"]
    [handle | _] = resp_headers["electric-handle"]

    url
    |> URI.parse()
    |> then(fn uri ->
      params =
        URI.decode_query(uri.query)
        |> Map.put("offset", offset)
        |> Map.put("handle", handle)

      %{uri | query: URI.encode_query(params)}
    end)
    |> URI.to_string()
  end

  defp fold_operations(acc, body) when is_list(body) do
    Enum.reduce(body, acc, fn
      %{"headers" => %{"operation" => "insert"}, "key" => key, "value" => value}, acc ->
        Map.put(acc, key, value)

      %{"headers" => %{"operation" => "update"}, "key" => key, "value" => value}, acc ->
        Map.update(acc, key, value, &Map.merge(&1, value))

      %{"headers" => %{"operation" => "delete"}, "key" => key}, acc ->
        Map.delete(acc, key)

      _, acc ->
        acc
    end)
  end

  defp fold_operations(acc, _), do: acc

  defp log_entry(method, url, req_headers, req_body, %{status: s, body: b, headers: h}, ts) do
    resp_body =
      if is_map(b) or is_list(b), do: Jason.encode!(b, pretty: true), else: inspect(b)

    build_log(method, url, req_headers, req_body, s, format_headers(h), resp_body, ts)
  end

  defp log_entry(method, url, req_headers, req_body, error, ts) do
    build_log(method, url, req_headers, req_body, 0, [], "Error: #{inspect(error)}", ts)
  end

  defp build_log(method, url, req_headers, req_body, status, resp_headers, resp_body, ts) do
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

  defp format_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {k, Enum.join(v, ", ")} end)
  end

  defp format_headers(headers) when is_list(headers), do: headers
  defp format_headers(_), do: []
end
