defmodule ChatWeb.DeviceLogController do
  @moduledoc "Backup functionality that should be moved into system secret room"
  use ChatWeb, :controller

  alias Phoenix.PubSub

  @incoming_topic "platform->chat"
  @outgoing_topic "chat->platform"

  def log(conn, _) do
    PubSub.subscribe(Chat.PubSub, @incoming_topic)
    PubSub.broadcast(Chat.PubSub, @outgoing_topic, :get_device_log)

    body =
      receive do
        {:platform_response, {:device_log, log}} ->
          log
          |> Enum.map_join("\n", fn {level, {_module, msg, {{a, b, c}, {d, e, f, g}}, _extra}} ->
            date = NaiveDateTime.new!(a, b, c, d, e, f, g * 1000)
            "#{date} [#{level}] #{msg}"
          end)
      after
        :timer.seconds(10) ->
          "Timeout"
      end

    conn
    # |> put_resp_header("content-disposition", "attachment; filename=\"device_log.txt\"")
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def reset(conn, _) do
    body =
      if Application.get_env(:chat, ChatWeb.Endpoint, [])[:allow_reset_data] do
        Chat.Db.db() |> CubDB.clear()
        "clear"
      else
        "skip"
      end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def dump_data_keys(conn, _) do
    body =
      Chat.Db.db()
      |> CubDB.select()
      |> Stream.map(fn {key, _} -> inspect(key) end)
      |> Enum.join("\n")

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end
end
