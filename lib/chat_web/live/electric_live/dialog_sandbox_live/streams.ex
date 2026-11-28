defmodule ChatWeb.ElectricLive.DialogSandboxLive.Streams do
  @moduledoc """
  Live shape streams of the selected dialog: messages, reactions and receipts.
  Each runs in its own process and reports back to the LiveView.
  """

  import ChatWeb.LiveHelpers, only: [public_url: 1]
  import Phoenix.Component, only: [assign: 2]

  alias ChatWeb.ElectricLive.DialogSandboxLive.{ApiClient, Keys}

  @doc "Starts the dialog streams unless they are already running."
  def maybe_start_stream(socket, dialog_hash) do
    case socket.assigns.sync_status do
      :idle -> start_dialog_stream(socket, dialog_hash)
      _ -> socket
    end
  end

  @doc "Restarts the message, reaction and receipt streams for `dialog_hash`."
  def start_dialog_stream(socket, dialog_hash) do
    socket = stop_dialog_stream(socket)
    base_url = public_url(socket)
    me = self()
    auth = Keys.auth(socket)

    socket
    |> assign(
      stream_pid: ApiClient.start_message_stream(dialog_hash, base_url, me, auth),
      reaction_stream_pid: ApiClient.start_reaction_stream(dialog_hash, base_url, me, auth),
      receipt_stream_pid: ApiClient.start_receipt_stream(dialog_hash, base_url, me, auth),
      sync_status: :loading
    )
  end

  defp stop_dialog_stream(socket) do
    for key <- [:stream_pid, :reaction_stream_pid, :receipt_stream_pid] do
      case socket.assigns[key] do
        pid when is_pid(pid) -> Process.exit(pid, :kill)
        _ -> :ok
      end
    end

    assign(socket, stream_pid: nil, reaction_stream_pid: nil, receipt_stream_pid: nil)
  end
end
