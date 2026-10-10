defmodule ChatWeb.Plugs.ElectricReadGate do
  @moduledoc """
  Gates synced-data reads in `trust` mode with a per-shape read session.

  The shape is taken from `opts[:shape]` when given (file chunk routes), else
  derived from the `table` param (run after `ElectricTableGuard`). The request
  must carry `Authorization: Bearer <token>` from a session for that shape.

  No signature or chain check here — both happened when the session was opened
  (see `Chat.Pq.ReadGate.open_session/4`). Passing responses are marked
  `cache-control: private` + `vary: authorization` so shared caches and the
  frontend service worker cannot replay gated data.
  """

  import Plug.Conn

  alias Chat.Data.Shapes
  alias Chat.Pq.ReadGate
  alias Chat.Pq.ReadSession

  def init(opts), do: opts

  @exempt_shapes [:user_card, :vouch_token]

  def call(conn, opts) do
    if ReadGate.enforced?() do
      {conn, shape} = requested_shape(conn, opts)

      if shape in @exempt_shapes do
        conn
      else
        case conn |> bearer_token() |> ReadSession.lookup() do
          {:ok, %{shape: ^shape}} -> register_before_send(conn, &make_private/1)
          _ -> reject(conn, shape)
        end
      end
    else
      conn
    end
  end

  defp requested_shape(conn, opts) do
    case Keyword.fetch(opts, :shape) do
      {:ok, shape} ->
        {conn, shape}

      :error ->
        conn = fetch_query_params(conn)
        {conn, Shapes.shape_name_for_table(conn.params["table"])}
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> String.trim(token)
      _ -> nil
    end
  end

  defp make_private(conn) do
    conn
    |> put_resp_header("cache-control", private_cache_control(conn))
    |> put_resp_header("vary", vary_with_authorization(conn))
  end

  defp private_cache_control(conn) do
    conn
    |> get_resp_header("cache-control")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "public", "private"]))
    |> then(&Enum.join(["private" | &1], ", "))
  end

  defp vary_with_authorization(conn) do
    case get_resp_header(conn, "vary") do
      [value | _] when value != "" -> value <> ", authorization"
      _ -> "authorization"
    end
  end

  defp reject(conn, shape) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "read_session_required", shape: shape}))
    |> halt()
  end
end
