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
    |> send_file(200, Db.db() |> CubDB.current_db_file())
  rescue
    _ ->
      conn
      |> send_resp(404, "")
  end

  def device_log(conn, %{"key" => key}) do
    body = Chat.Broker.get(key)

    conn
    |> put_resp_header("content-disposition", "attachment; filename=\"device_log.txt\"")
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def lsmod(conn, _) do
    {output, _} = System.cmd("lsmod", [])

    conn |> send_resp(200, output)
  rescue
    _ -> conn |> send_resp(404, "")
  end

  def modprobe(conn, _) do
    {output, _} = System.cmd("modprobe", ["-l"])

    conn |> send_resp(200, output)
  rescue
    _ -> conn |> send_resp(404, "")
  end
end
