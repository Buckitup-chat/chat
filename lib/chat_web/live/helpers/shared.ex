defmodule ChatWeb.LiveHelpers.Shared do
  @moduledoc "Common functions"

  require Logger

  alias Phoenix.LiveView
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Socket

  @type js() :: %JS{ops: list()}

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
