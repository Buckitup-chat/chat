defmodule ChatWeb.ElectricLive.OriginBotsLive.Index do
  @moduledoc "LiveView listing all origin bots synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :origin_bots,
    table: "origin_bots",
    schema: Chat.Data.Schemas.OriginBot

  defp dom_id(%OriginBot{bot_hash: hash}), do: "ob-#{Base.encode16(hash, case: :lower)}"

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Origin Bots (Electric)"
      subtitle="Bot identities per origin synced via Electric"
      stream_header="Origin Bots Stream"
      loading_text="Syncing origin bots from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="origin_bots" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, bot} <- @streams.origin_bots}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-gray-900 truncate">
                Bot: <span class="font-mono">{Shortcode.short_code(bot.bot_hash)}</span>
                <span
                  :if={bot.deleted_flag}
                  class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800"
                >
                  Deleted
                </span>
              </p>
              <p class="mt-1 text-xs text-gray-500">
                Origin: <span class="font-mono">{Shortcode.short_code(bot.origin_hash)}</span>
              </p>
              <p class="mt-1 text-xs text-gray-500">
                Timestamp: {bot.owner_timestamp}
              </p>
            </div>
          </div>
        </div>
      </:row>
    </StreamIndex.page>
    """
  end
end
