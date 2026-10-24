defmodule ChatWeb.ElectricLive.ReviewWriteTokensLive.Index do
  @moduledoc "LiveView listing all review write tokens synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :review_write_tokens,
    table: "review_write_tokens",
    schema: Chat.Data.Schemas.ReviewWriteToken

  defp dom_id(%ReviewWriteToken{nonce: nonce}), do: "rwt-#{nonce}"

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Review Write Tokens (Electric)"
      subtitle="Token lifecycle rows synced via Electric"
      stream_header="Review Write Tokens Stream"
      loading_text="Syncing review write tokens from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="review_write_tokens" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, token} <- @streams.review_write_tokens}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-gray-900 truncate">
                Nonce: <span class="font-mono">{token.nonce}</span>
                <span
                  :if={token.deleted_flag}
                  class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800"
                >
                  Deleted
                </span>
              </p>
              <p class="mt-1 text-xs text-gray-500">
                Origin: <span class="font-mono">{Shortcode.short_code(token.origin_hash)}</span>
                | Bot: <span class="font-mono">{Shortcode.short_code(token.review_bot_hash)}</span>
              </p>
              <p class="mt-1 text-xs text-gray-500">
                User: <span class="font-mono">{Shortcode.short_code(token.user_hash)}</span>
                | Review: <span class="font-mono">{Shortcode.short_code(token.review_hash)}</span>
              </p>
              <p class="mt-1 text-xs text-gray-500">
                Timestamp: {token.owner_timestamp}
              </p>
            </div>
          </div>
        </div>
      </:row>
    </StreamIndex.page>
    """
  end
end
