defmodule ChatWeb.ElectricLive.ReviewPostRightsLive.Index do
  @moduledoc "LiveView listing review post rights synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :records,
    table: "review_post_right",
    schema: Chat.Data.Schemas.ReviewPostRight

  defp dom_id(%ReviewPostRight{review_hash: hash}),
    do: "rpr-#{Shortcode.short_code(hash)}"

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Review Post Rights (Electric)"
      subtitle="KEM-encrypted envelopes for publishing reviews"
      stream_header="Review Post Rights Stream"
      loading_text="Syncing review post rights from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="records" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, record} <- @streams.records}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="flex items-center justify-between">
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-gray-900 truncate">
                  Review:
                  <span class="font-mono text-xs">
                    {Shortcode.short_code(record.review_hash)}
                  </span>
                  <span
                    :if={record.deleted_flag}
                    class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800"
                  >
                    Deleted
                  </span>
                </p>
                <p class="mt-1 text-xs text-gray-500">
                  Origin: <span class="font-mono">{Shortcode.short_code(record.origin_hash)}</span>
                  | Author: <span class="font-mono">{Shortcode.short_code(record.author_hash)}</span>
                </p>
                <p class="mt-1 text-xs text-gray-500">
                  Sign: <span class="font-mono">{Shortcode.short_code(record.sign_hash)}</span>
                  | Timestamp: {record.owner_timestamp}
                </p>
              </div>
            </div>
          </div>
        </div>
      </:row>
    </StreamIndex.page>
    """
  end
end
