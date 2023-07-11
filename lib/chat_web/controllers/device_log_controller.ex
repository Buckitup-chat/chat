defmodule ChatWeb.DeviceLogController do
  @moduledoc "Backup functionality that should be moved into system secret room"
  use ChatWeb, :controller

  alias Phoenix.PubSub

  alias Chat.AdminDb.AdminLogger

  @incoming_topic "platform->chat"
  @outgoing_topic "chat->platform"

  def log(conn, _) do
    PubSub.subscribe(Chat.PubSub, @incoming_topic)
    PubSub.broadcast(Chat.PubSub, @outgoing_topic, :get_device_log)

    receive do
      {:platform_response, {:device_log, {ram_log, log}}} ->
        first =
          if ram_log do
            ram_log <> "\n-----------------------------\n\n"
          else
            ""
          end

        second =
          Enum.map_join(log, "\n", fn {level, {_module, msg, extended_erl_date, _extra}} ->
            date = convert_extended_erl_date(extended_erl_date)
            "#{date} [#{level}] #{msg}"
          end)

        first <> second
    after
      :timer.seconds(10) ->
        "Timeout"
    end
    |> send_text(conn)

    # conn
    # # |> put_resp_header("content-disposition", "attachment; filename=\"device_log.txt\"")
    # |> put_resp_content_type("text/plain")
    # |> send_resp(200, body)
  end

  def reset(conn, _) do
    body =
      if Application.get_env(:chat, ChatWeb.Endpoint, [])[:allow_reset_data] do
        Chat.Db.db() |> CubDB.clear()
        "<html><body>clear</body></html>"
      else
        "skip"
      end

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, body)
  end

  def dump_data_keys(conn, _) do
    Chat.Db.db()
    |> CubDB.select()
    |> Stream.map(fn {key, _} -> inspect(key) end)
    |> Enum.join("\n")
    |> send_text(conn)
  end

  def db_log(conn, _) do
    AdminLogger.get_log()
    |> format_db_log()
    |> send_text(conn)
  end

  def db_log_prev(conn, _) do
    AdminLogger.get_log(:prev)
    |> format_db_log()
    |> send_text(conn)
  end

  def db_log_prev_prev(conn, _) do
    AdminLogger.get_log(:prev_prev)
    |> format_db_log()
    |> send_text(conn)
  end

  defp format_db_log(log) do
    log
    |> Enum.map_join("\n", fn {_, {extended_erl_date, level, io_list}} ->
      extended_erl_date
      |> convert_extended_erl_date()
      |> NaiveDateTime.to_string()
      |> then(&[&1, " [", level |> to_string(), "] ", io_list])
      |> IO.iodata_to_binary()
    end)
  end

  defp convert_extended_erl_date({{a, b, c}, {d, e, f, g}}) do
    NaiveDateTime.new!(a, b, c, d, e, f, g * 1000)
  end

  defp send_text(body, conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end
end
