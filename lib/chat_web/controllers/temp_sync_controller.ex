defmodule ChatWeb.TempSyncController do
  @moduledoc "Backup functionality that should be moved into system secret room"
  use ChatWeb, :controller

  alias Chat.Db

  def backup(conn, _) do
    date_str = DateTime.utc_now() |> DateTime.to_string()
    filename = "backup_#{date_str}.cub"

    conn
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> put_resp_content_type("application/octet-stream")
    |> send_resp(200, Db.db() |> CubDB.current_db_file() |> File.read!())
  rescue
    _ ->
      conn
      |> send_resp(404, "")
  end
end
