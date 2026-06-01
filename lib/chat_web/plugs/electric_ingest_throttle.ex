defmodule ChatWeb.Plugs.ElectricIngestThrottle do
  @moduledoc """
  Admission control for heavy file-chunk ingest requests.

  Only ingest payloads that write to `file_chunks` (the ~4 MB blob inserts) are
  gated; cheap mutations (`files` manifests, `user_cards`, …) pass straight
  through. When the `Chat.Upload.IngestThrottle` semaphore is full, the request
  is rejected with `429 Too Many Requests` and a `Retry-After` header so the
  client can back off and retry — instead of queueing behind a saturated
  connection pool and timing out.

  On success the token is released from a `before_send` callback (and, as a
  safety net, automatically when the request process exits — the throttle
  monitors the caller).
  """

  import Plug.Conn

  alias Chat.Upload.IngestThrottle

  def init(opts), do: opts

  def call(conn, opts) do
    if heavy_ingest?(conn.params) do
      gate(conn, Keyword.get(opts, :throttle, IngestThrottle))
    else
      conn
    end
  end

  defp gate(conn, throttle) do
    case IngestThrottle.checkout(throttle) do
      :ok ->
        register_before_send(conn, fn conn ->
          IngestThrottle.checkin(throttle)
          conn
        end)

      {:busy, retry_after_seconds} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
        |> put_resp_content_type("application/json")
        |> send_resp(
          429,
          Jason.encode!(%{error: "upload_busy", retry_after: retry_after_seconds})
        )
        |> halt()
    end
  end

  defp heavy_ingest?(%{"mutations" => mutations}) when is_list(mutations) do
    Enum.any?(mutations, &touches_file_chunks?/1)
  end

  defp heavy_ingest?(_params), do: false

  defp touches_file_chunks?(%{"syncMetadata" => %{"relation" => relation}}) do
    relation_name(relation) == "file_chunks"
  end

  defp touches_file_chunks?(_mutation), do: false

  # Tolerate relation given as a bare string ("file_chunks") or a
  # schema-qualified list (["public", "file_chunks"]).
  defp relation_name(relation) when is_binary(relation), do: relation
  defp relation_name(relation) when is_list(relation), do: List.last(relation)
  defp relation_name(_relation), do: nil
end
