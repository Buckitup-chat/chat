defmodule ChatWeb.Plugs.ElectricTableGuard do
  @moduledoc """
  Rejects Electric shape requests for tables not in the allowed list.

  Allowed tables are derived at compile time from Chat.Data.Shapes registry,
  including version schemas.
  """

  import Plug.Conn

  @allowed_tables Chat.Data.Shapes.all()
                  |> Enum.flat_map(fn shape ->
                    [shape.schema_module() | List.wrap(shape.versions_schema())]
                  end)
                  |> Enum.map(& &1.__schema__(:source))

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    case conn.params["table"] do
      table when table in @allowed_tables ->
        conn

      nil ->
        reject(conn, "missing table parameter")

      table ->
        reject(conn, "table #{inspect(table)} is not allowed")
    end
  end

  defp reject(conn, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, Jason.encode!(%{error: message}))
    |> halt()
  end
end
