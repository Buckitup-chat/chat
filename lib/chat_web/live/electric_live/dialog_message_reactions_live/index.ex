defmodule ChatWeb.ElectricLive.DialogMessageReactionsLive.Index do
  @moduledoc "LiveView listing dialog message reactions synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :dialog_message_reactions,
    table: "dialog_message_reactions",
    schema: Chat.Data.Schemas.DialogMessageReaction

  defp dom_id(%DialogMessageReaction{reaction_hash: rh}), do: "dmr-#{short_hex(rh)}"

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Dialog Reactions Stream (LiveView + Electric)"
      subtitle="Real-time encrypted emoji reactions on dialog messages"
      stream_header="Dialog Message Reactions Stream"
      loading_text="Syncing reactions from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="dialog_message_reactions" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, rxn} <- @streams.dialog_message_reactions}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center min-w-0 flex-1">
                <div class="flex-shrink-0">
                  <div class="h-12 w-12 rounded-full bg-pink-600 flex items-center justify-center">
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
                        d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                  </div>
                </div>
                <div class="min-w-0 flex-1 px-4">
                  <p class="text-sm font-medium text-gray-900 font-mono truncate">
                    reaction: {short_hex(rxn.reaction_hash)}
                    <%= if rxn.deleted_flag do %>
                      <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
                        Deleted
                      </span>
                    <% end %>
                  </p>
                  <p class="mt-1 text-sm text-gray-500 font-mono truncate">
                    msg: {rxn.message_id} &middot; reactor: {short_hex(rxn.reactor_hash)}
                  </p>
                  <p class="mt-1 text-xs text-gray-400">
                    dialog: {short_hex(rxn.dialog_hash)} &middot;
                    Timestamp: {rxn.owner_timestamp}
                  </p>
                </div>
              </div>
              <div class="ml-5 flex-shrink-0">
                <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if rxn.deleted_flag, do: "bg-red-100 text-red-800", else: "bg-green-100 text-green-800"}"}>
                  {if rxn.deleted_flag, do: "Deleted", else: "Synced"}
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
