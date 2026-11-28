defmodule ChatWeb.ElectricLive.SandboxHttp.Log do
  @moduledoc "Request log entries shown by the sandboxes for every HTTP call."

  @doc "Log entry from a `Req` response, or from a transport error."
  def log_entry(method, url, req_headers, req_body, %{status: s, body: b, headers: h}, ts) do
    resp_body =
      if is_map(b) or is_list(b), do: Jason.encode!(b, pretty: true), else: inspect(b)

    build_log(method, url, req_headers, req_body, s, format_headers(h), resp_body, ts)
  end

  def log_entry(method, url, req_headers, req_body, error, ts) do
    build_log(method, url, req_headers, req_body, 0, [], "Error: #{inspect(error)}", ts)
  end

  @doc "Log entry from its parts."
  def build_log(method, url, req_headers, req_body, status, resp_headers, resp_body, ts) do
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

  @doc "Log entry for a successful shape read."
  def shape_log(url, headers, rows, timestamp) do
    build_log("GET", url, headers, "", 200, [], Jason.encode!(rows, pretty: true), timestamp)
  end

  @doc "Response headers as a list of `{name, value}` pairs."
  def format_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {k, Enum.join(v, ", ")} end)
  end

  def format_headers(headers) when is_list(headers), do: headers
  def format_headers(_), do: []
end
