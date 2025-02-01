defmodule Proxy.SocketClient do
  @moduledoc "WebSocket client"

  import Tools.SocketPrivate

  @pid_key :websocket_client_pid
  @queue_key :websocket_client_queue

  def connect(socket, args) do
    socket
    |> connect_websocket_client(args)
    |> send_deffered_messages()
  end

  def join(socket, topic) do
    if connected?(socket) do
      join_topic(socket, topic)
    else
      deffer_join(socket, topic)
    end
  end

  def leave(socket, topic) do
    if connected?(socket) do
      leave_topic(socket, topic)
    else
      deffer_leave(socket, topic)
    end
  end

  defp connect_websocket_client(socket, args) do
    server = socket |> get_private(:server)

    {:ok, pid} =
      Proxy.SocketClient.ChannelClient.start_link(
        Keyword.merge(args, uri: "ws://#{server}/proxy-socket/websocket")
      )

    socket
    |> set_private(@pid_key, pid)
  end

  defp send_deffered_messages(socket) do
    pid = socket |> get_socket_client_pid()

    socket
    |> get_private(@queue_key, [])
    |> Enum.reverse()
    |> Enum.each(&send(pid, &1))

    socket |> set_private(@queue_key, [])
  end

  defp join_topic(socket, topic) do
    socket
    |> get_socket_client_pid()
    |> send({:join, topic})

    socket
  end

  defp leave_topic(socket, topic) do
    socket
    |> get_socket_client_pid()
    |> send({:leave, topic})
  end

  defp get_socket_client_pid(socket) do
    socket
    |> get_private(@pid_key)
  end

  defp connected?(socket) do
    pid = socket |> get_socket_client_pid()

    is_pid(pid) and Process.alive?(pid)
  end

  defp deffer_join(socket, topic) do
    socket
    |> update_private(@queue_key, &[{:join, topic} | &1], [])
  end

  defp deffer_leave(socket, topic) do
    socket
    |> update_private(@queue_key, &[{:leave, topic} | &1], [])
  end
end
