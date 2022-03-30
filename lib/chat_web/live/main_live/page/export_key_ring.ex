defmodule ChatWeb.MainLive.Page.ExportKeyRing do
  @moduledoc "Export Key Ring Page"
  import Phoenix.LiveView, only: [assign: 3]

  alias Chat.KeyRingTokens
  alias Chat.Log

  def init(socket, uuid) do
    socket
    |> assign(:mode, :export_key_ring)
    |> assign(:export_id, uuid)
    |> assign(:export_result, false)
  end

  def send_key_ring(%{assigns: %{me: me, rooms: rooms, export_id: export_id}} = socket, code) do
    case KeyRingTokens.get(export_id, code) do
      {:ok, pid} ->
        send(pid, {:exported_key_ring, {me, rooms}})
        Log.export_keys(me)

        socket
        |> assign(:export_result, :ok)

      _ ->
        socket
        |> error()
    end
  end

  def send_key_ring(socket, _code) do
    socket
    |> error()
  end

  def error(socket) do
    socket
    |> assign(:export_result, :error)
  end
end
