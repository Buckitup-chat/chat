defmodule ChatWeb.ElectricLive.DialogSandboxLive.Receipts do
  @moduledoc "Delivery and read receipts of the selected dialog."

  import ChatWeb.LiveHelpers, only: [public_url: 1]
  import Phoenix.Component, only: [assign: 3, update: 3]

  alias ChatWeb.ElectricLive.DialogSandboxLive.{ApiClient, Crypto, Keys}

  @doc "Publishes a receipt of `type` for a message."
  def send_receipt(socket, msg_id, sign_hash, type) do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    dialog = Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == dialog_hash))
    base_url = public_url(socket)

    with {:ok, socket} <- Keys.ensure_dialog_key(socket, user, dialog.peer_hash, base_url),
         {:ok, %{log_entries: logs}} <-
           ApiClient.publish_receipt(user, dialog_hash, msg_id, sign_hash, type, base_url) do
      update(socket, :request_log, &(&1 ++ logs))
    else
      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(:error_message, reason)
        |> update(:request_log, &(&1 ++ logs))
    end
  end

  @doc "Initial stream load: groups receipts by message."
  def loaded(socket, raw_receipts) do
    assign(socket, :receipts, Crypto.group_receipts_by_message(raw_receipts))
  end

  @doc "Adds a streamed receipt unless the same peer already sent that type."
  def changed(socket, raw) do
    receipt = %{
      message_id: raw["message_id"],
      message_sign_hash: raw["message_sign_hash"],
      peer_hash: raw["peer_hash"],
      type: raw["type"]
    }

    receipts =
      Map.update(socket.assigns.receipts, receipt.message_id, [receipt], fn list ->
        if Enum.any?(list, &(&1.peer_hash == receipt.peer_hash and &1.type == receipt.type)) do
          list
        else
          list ++ [receipt]
        end
      end)

    assign(socket, :receipts, receipts)
  end
end
