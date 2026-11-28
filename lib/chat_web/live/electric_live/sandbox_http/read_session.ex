defmodule ChatWeb.ElectricLive.SandboxHttp.ReadSession do
  @moduledoc "Read sessions for gated shapes: `GET /challenge` → sign → `POST /read_session`."

  import ChatWeb.ElectricLive.SandboxHttp.Ingest, only: [get_challenge: 1]
  import ChatWeb.ElectricLive.SandboxHttp.Log, only: [log_entry: 6]

  alias Chat.TimeKeeper

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
          {:error, body_error(resp.body) || "Read session failed: #{resp.status}",
           [challenge_log, log_entry("POST", url, headers, body_json, resp, timestamp)]}

        {:error, error} ->
          {:error, "Read session failed: #{inspect(error)}",
           [challenge_log, log_entry("POST", url, headers, body_json, error, timestamp)]}
      end
    end
  end

  defp body_error(%{} = body), do: body["error"]
  defp body_error(_body), do: nil
end
