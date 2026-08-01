defmodule ChatWeb.ElectricLive.OriginSandboxLive.Http do
  @moduledoc false

  alias Chat.TimeKeeper

  def get_challenge(base_url) do
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

  def post_ingest(challenge_resp, payload, sign_skey, base_url) do
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

  def encode_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)

  defp log_entry(
         method,
         url,
         req_headers,
         req_body,
         %{status: status, body: body, headers: headers},
         ts
       ) do
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
end
