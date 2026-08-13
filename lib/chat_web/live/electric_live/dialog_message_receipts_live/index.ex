defmodule ChatWeb.ElectricLive.DialogMessageReceiptsLive.Index do
  @moduledoc "LiveView listing dialog message receipts synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :dialog_message_receipts,
    table: "dialog_message_receipts",
    schema: Chat.Data.Schemas.DialogMessageReceipt

  defp dom_id(%DialogMessageReceipt{receipt_hash: rh}), do: "dmrc-#{short_hex(rh)}"

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Dialog Receipts Stream (LiveView + Electric)"
      subtitle="Real-time delivery and read receipts for dialog messages"
      stream_header="Dialog Message Receipts Stream"
      loading_text="Syncing receipts from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="dialog_message_receipts" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, rcpt} <- @streams.dialog_message_receipts}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center min-w-0 flex-1">
                <div class="flex-shrink-0">
                  <div class={"h-12 w-12 rounded-full flex items-center justify-center #{receipt_color(rcpt.type)}"}>
                    <svg
                      class="h-6 w-6 text-white"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d={receipt_icon(rcpt.type)}
                      />
                    </svg>
                  </div>
                </div>
                <div class="min-w-0 flex-1 px-4">
                  <p class="text-sm font-medium text-gray-900 font-mono truncate">
                    receipt: {short_hex(rcpt.receipt_hash)}
                  </p>
                  <p class="mt-1 text-sm text-gray-500 font-mono truncate">
                    msg: {rcpt.message_id} &middot; peer: {short_hex(rcpt.peer_hash)}
                  </p>
                  <p class="mt-1 text-xs text-gray-400">
                    dialog: {short_hex(rcpt.dialog_hash)} &middot;
                    type: {rcpt.type} &middot;
                    Timestamp: {rcpt.owner_timestamp}
                  </p>
                </div>
              </div>
              <div class="ml-5 flex-shrink-0">
                <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{receipt_badge(rcpt.type)}"}>
                  {String.capitalize(rcpt.type || "unknown")}
                </span>
              </div>
            </div>
          </div>
        </div>
      </:row>
    </StreamIndex.page>
    """
  end

  defp short_hex(nil), do: "nil"

  defp short_hex(bin) when is_binary(bin),
    do: bin |> Base.encode16(case: :lower) |> String.slice(0, 12)

  defp receipt_color("read"), do: "bg-blue-600"
  defp receipt_color("delivered"), do: "bg-emerald-600"
  defp receipt_color(_), do: "bg-gray-600"

  defp receipt_icon("read"),
    do:
      "M15 12a3 3 0 11-6 0 3 3 0 016 0z M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"

  defp receipt_icon("delivered"), do: "M5 13l4 4L19 7"

  defp receipt_icon(_),
    do:
      "M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01"

  defp receipt_badge("read"), do: "bg-blue-100 text-blue-800"
  defp receipt_badge("delivered"), do: "bg-emerald-100 text-emerald-800"
  defp receipt_badge(_), do: "bg-gray-100 text-gray-800"
end
