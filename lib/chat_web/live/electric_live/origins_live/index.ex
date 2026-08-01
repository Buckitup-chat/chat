defmodule ChatWeb.ElectricLive.OriginsLive.Index do
  @moduledoc "LiveView listing all origins synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :origins,
    table: "origins",
    schema: Chat.Data.Schemas.Origin

  defp dom_id(%Origin{origin_hash: hash}), do: "origin-#{Base.encode16(hash, case: :lower)}"

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Origins (Electric)"
      subtitle="Real-time origin directory synced via Electric"
      stream_header="Origins Stream"
      loading_text="Syncing origins from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="origins" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, origin} <- @streams.origins}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="flex items-center justify-between">
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-gray-900 truncate">
                  {origin.name}
                  <span class="ml-2 font-mono text-xs text-gray-500">
                    {Shortcode.short_code(origin.origin_hash)}
                  </span>
                  <span
                    :if={origin.deleted_flag}
                    class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800"
                  >
                    Deleted
                  </span>
                </p>
                <p class="mt-1 text-xs text-gray-500">
                  Owner: <span class="font-mono">{Shortcode.short_code(origin.owner_hash)}</span>
                </p>
                <p class="mt-1 text-xs text-gray-500">
                  Moderation: <span class="font-semibold">{origin.moderation_mode}</span>
                  | Timestamp: {origin.owner_timestamp}
                </p>
              </div>
              <div class="ml-5 flex-shrink-0">
                <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{moderation_badge(origin.moderation_mode)}"}>
                  {origin.moderation_mode}
                </span>
              </div>
            </div>
          </div>
        </div>
      </:row>
    </StreamIndex.page>
    """
  end

  defp moderation_badge(:none), do: "bg-gray-100 text-gray-800"
  defp moderation_badge(:post), do: "bg-yellow-100 text-yellow-800"
  defp moderation_badge(:pre), do: "bg-blue-100 text-blue-800"
  defp moderation_badge(_), do: "bg-gray-100 text-gray-800"
end
