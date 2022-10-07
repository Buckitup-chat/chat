defmodule ChatWeb.DeviceLogController do
  @moduledoc "Dump devide log"
  use ChatWeb, :controller

  alias Phoenix.PubSub

  @incoming_topic "platform->chat"
  @outgoing_topic "chat->platform"

  def log(conn, _) do
    PubSub.subscribe(Chat.PubSub, @incoming_topic)
    PubSub.broadcast(Chat.PubSub, @outgoing_topic, :device_log)

    body =
      receive do
        {:device_log, log} -> log
      after
        :timer.seconds(3) ->
          "Timeout"
      end

    conn
    # |> put_resp_header("content-disposition", "attachment; filename=\"device_log.txt\"")
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end
end
