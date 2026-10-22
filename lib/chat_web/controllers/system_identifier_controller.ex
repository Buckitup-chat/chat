defmodule ChatWeb.SystemIdentifierController do
  use ChatWeb, :controller

  import Chat.Db, only: [repo: 0]

  alias Chat.Pq.OwnerBootstrap
  alias Ecto.Adapters.SQL
  alias Postgrex.Result

  def show(conn, _params) do
    case OwnerBootstrap.owner() do
      nil ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "device not activated"})

      _owner ->
        serve_system_identifier(conn)
    end
  end

  defp serve_system_identifier(conn) do
    case query_system_identifier() do
      {:ok, identifier} ->
        json(conn, %{system_identifier: identifier})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: to_string(reason)})
    end
  end

  defp query_system_identifier do
    case SQL.query(repo(), "SELECT system_identifier FROM pg_control_system()", []) do
      {:ok, %Result{rows: [[identifier]]}} ->
        {:ok, to_string(identifier)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
