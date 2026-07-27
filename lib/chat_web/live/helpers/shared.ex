defmodule ChatWeb.LiveHelpers.Shared do
  @moduledoc "Common functions"

  require Logger

  alias Phoenix.LiveView
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Socket

  @type js() :: %JS{ops: list()}

  @doc """
  Base URL the browser used to reach this LiveView, taken from `socket.host_uri`.

  This is the publicly reachable address rather than a configured endpoint, so
  it is what a client-side reference implementation must call back into.
  """
  @spec public_url(Socket.t()) :: String.t()
  def public_url(%Socket{host_uri: uri}) do
    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end

  @spec send_js(Socket.t(), js()) :: Socket.t()
  def send_js(%Socket{} = socket, %JS{ops: ops}) do
    LiveView.push_event(socket, "js-event", %{data: Jason.encode!(ops)})
  end

  @spec process(Socket.t(), fun()) :: Socket.t()
  def process(socket, task) do
    pid = Process.whereis(Chat.TaskSupervisor)

    if is_pid(pid) and Process.alive?(pid) do
      Task.Supervisor.start_child(pid, fn ->
        try do
          socket |> task.()

          :ok
        rescue
          reason -> Logger.error([inspect(reason)])
        end
      end)
    else
      Logger.warning("[chat] [UI] Chat.TaskSupervisor is not running")
    end

    socket
  end
end
