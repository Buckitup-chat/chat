defmodule ChatWeb.ElectricLive.SandboxHttp.Ingest do
  @moduledoc "Writes: `GET /electric/v1/challenge` + signed `POST /electric/v1/ingest`."

  import ChatWeb.ElectricLive.SandboxHttp.Log, only: [log_entry: 6]

  alias Chat.TimeKeeper

  @doc "Requests a fresh challenge from the peer."
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

  @doc "Signs `challenge_resp` and posts `payload` to the ingest endpoint."
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

  @doc "Challenge + ingest in one call; logs of both requests are returned."
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
end
