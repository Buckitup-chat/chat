defmodule ChatWeb.LiveHelpers.Shared do
  @moduledoc "Common functions"
  alias Phoenix.LiveView
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Socket

  @type js() :: %JS{ops: list()}

  @spec send_js(Socket.t(), js()) :: Socket.t()
  def send_js(%Socket{} = socket, %JS{ops: ops}) do
    LiveView.push_event(socket, "js-event", %{data: Jason.encode!(ops)})
  end
end
