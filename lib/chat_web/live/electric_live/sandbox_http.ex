defmodule ChatWeb.ElectricLive.SandboxHttp do
  @moduledoc """
  Shared HTTP client for Electric sandbox operations.

  Sandboxes are reference implementations for external clients — all reads and
  writes go through raw HTTP, never through `Electric.Client`, `ShapeReader`,
  `Ecto`, or `Db.repo()`.

  Facade over `SandboxHttp.Ingest` (challenge + ingest writes),
  `SandboxHttp.ReadSession`, `SandboxHttp.Gated` (gated shape reads),
  `SandboxHttp.ShapePages` (paging + folding) and `SandboxHttp.Log`.
  """

  import ChatWeb.ElectricLive.SandboxHttp.Log, only: [build_log: 8, format_headers: 1]
  import ChatWeb.ElectricLive.SandboxHttp.ShapePages, only: [fetch_pages: 3, shape_url: 3]

  alias Chat.Data.Integrity
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.SandboxHttp.Gated
  alias ChatWeb.ElectricLive.SandboxHttp.Ingest
  alias ChatWeb.ElectricLive.SandboxHttp.ReadSession

  # --- Shape reads ---

  def fetch_shape(base_url, table), do: fetch_shape(base_url, table, nil)

  def fetch_shape(base_url, table, where) do
    base_url
    |> shape_url(table, where)
    |> do_fetch_shape()
  end

  # --- Writes ---

  defdelegate get_challenge(base_url), to: Ingest
  defdelegate post_ingest(challenge_resp, payload, sign_skey, base_url), to: Ingest
  defdelegate ingest(payload, sign_skey, base_url), to: Ingest

  # --- Read sessions ---

  defdelegate open_read_session(base_url, shape, user_hash, sign_skey), to: ReadSession

  # --- Gated shape reads ---

  defdelegate fetch_shape_gated(base_url, table, auth), to: Gated
  defdelegate fetch_shape_gated(base_url, table, where, auth), to: Gated

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
end
