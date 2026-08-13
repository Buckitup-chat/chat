defmodule ChatWeb.ElectricLive.DialogKeysLive.Index do
  @moduledoc "LiveView listing dialog key exchange rows synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :dialog_keys,
    table: "dialog_keys",
    schema: Chat.Data.Schemas.DialogKey

  defp dom_id(%DialogKey{dialog_hash: dh, sender_hash: sh}) do
    "dk-#{Base.encode16(dh, case: :lower)}-#{Base.encode16(sh, case: :lower)}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Dialog Keys Stream (LiveView + Electric)"
      subtitle="Real-time dialog key exchange rows"
      stream_header="Dialog Keys Stream"
      loading_text="Syncing dialog keys from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="dialog_keys" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, dk} <- @streams.dialog_keys}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center min-w-0 flex-1">
                <div class="flex-shrink-0">
                  <div class="h-12 w-12 rounded-full bg-teal-600 flex items-center justify-center">
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
                        d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"
                      />
                    </svg>
                  </div>
                </div>
                <div class="min-w-0 flex-1 px-4">
                  <p class="text-sm font-medium text-gray-900 font-mono truncate">
                    dialog: {short_hex(dk.dialog_hash)}
                    <%= if dk.deleted_flag do %>
                      <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
                        Deleted
                      </span>
                    <% end %>
                  </p>
                  <p class="mt-1 text-sm text-gray-500 font-mono truncate">
                    sender: {short_hex(dk.sender_hash)} &rarr; peer: {short_hex(dk.peer_hash)}
                  </p>
                  <p class="mt-1 text-xs text-gray-400">
                    Timestamp: {dk.owner_timestamp}
                  </p>
                </div>
              </div>
              <div class="ml-5 flex-shrink-0">
                <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if dk.deleted_flag, do: "bg-red-100 text-red-800", else: "bg-green-100 text-green-800"}"}>
                  {if dk.deleted_flag, do: "Deleted", else: "Synced"}
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
end
