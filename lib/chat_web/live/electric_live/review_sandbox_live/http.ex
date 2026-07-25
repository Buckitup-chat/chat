defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Http do
  @moduledoc "HTTP infrastructure for review sandbox: challenge auth, ingest, logging."

  alias Chat.Data.Integrity
  alias Chat.TimeKeeper
  alias EnigmaPq

  def sign_struct(struct, sign_skey, hash_module) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> hash_module.from_binary()
    {sign_b64, sign_hash}
  end

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
    post_with_auth(challenge_resp, payload, sign_skey, base_url, "/ingest")
  end

  def encode_base64(bin), do: Base.encode64(bin, padding: false)

  defp post_with_auth(
         %{"challenge" => challenge, "challenge_id" => challenge_id},
         payload,
         sign_skey,
         base_url,
         path
       ) do
    signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)

    payload_with_auth =
      Map.put(payload, "auth", %{
        "challenge_id" => challenge_id,
        "signature" => Base.encode64(signature, padding: false)
      })

    url = base_url <> "/electric/v1" <> path
    req_headers = [{"accept", "application/json"}, {"content-type", "application/json"}]
    timestamp = TimeKeeper.now()
    body_json = Jason.encode!(payload_with_auth, pretty: true)

    case Req.post(url, json: payload_with_auth, headers: req_headers) do
      {:ok, %{status: status} = resp} when status in 200..299 ->
        {:ok, resp, log_entry("POST", url, req_headers, body_json, resp, timestamp)}

      {:ok, %{status: status} = resp} ->
        {:error, "Request failed: #{status}",
         [log_entry("POST", url, req_headers, body_json, resp, timestamp)]}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}",
         [log_entry("POST", url, req_headers, body_json, error, timestamp)]}
    end
  end

  defp log_entry(method, url, req_headers, req_body, response_or_error, ts) do
    {status, resp_headers, resp_body} =
      case response_or_error do
        %{status: status, body: body, headers: headers} ->
          formatted = if is_map(body), do: Jason.encode!(body, pretty: true), else: inspect(body)
          {status, resp_headers(headers), formatted}

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

  defp resp_headers(headers) when is_map(headers),
    do: Enum.map(headers, fn {k, v} -> {k, Enum.join(v, ", ")} end)

  defp resp_headers(headers) when is_list(headers), do: headers
end
