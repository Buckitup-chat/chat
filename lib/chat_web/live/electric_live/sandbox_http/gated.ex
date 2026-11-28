defmodule ChatWeb.ElectricLive.SandboxHttp.Gated do
  @moduledoc """
  Gated shape reads: a plain shape read that opens a read session on
  `401 read_session_required` and retries with the Bearer token.
  """

  import ChatWeb.ElectricLive.SandboxHttp.Log,
    only: [build_log: 8, format_headers: 1, shape_log: 4]

  import ChatWeb.ElectricLive.SandboxHttp.ReadSession, only: [open_read_session: 4]
  import ChatWeb.ElectricLive.SandboxHttp.ShapePages, only: [fetch_pages: 3, shape_url: 3]

  alias Chat.TimeKeeper

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
         [
           build_log(
             "GET",
             url,
             headers,
             "",
             status,
             format_headers(rh),
             inspect(body),
             timestamp
           )
         ]}

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
               [
                 build_log(
                   "GET",
                   url,
                   retry_headers,
                   "",
                   status,
                   format_headers(rh),
                   inspect(body),
                   retry_ts
                 )
               ]}

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
end
