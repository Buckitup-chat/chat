defmodule ChatWeb.ElectricLive.ReviewsLive.Index do
  @moduledoc "LiveView listing reviews synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :reviews,
    table: "review",
    schema: Chat.Data.Schemas.Review

  defp dom_id(%Review{review_hash: hash}), do: "review-#{hash}"

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Reviews (Electric)"
      subtitle="Real-time reviews synced via Electric"
      stream_header="Reviews Stream"
      loading_text="Syncing reviews from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="reviews" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, review} <- @streams.reviews}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="flex items-center justify-between">
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-gray-900 truncate">
                  Review:
                  <span class="font-mono text-xs">
                    {Shortcode.short_code(review.review_hash)}
                  </span>
                  <span
                    :if={review.deleted_flag}
                    class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800"
                  >
                    Deleted
                  </span>
                </p>
                <p class="mt-1 text-xs text-gray-500">
                  Origin: <span class="font-mono">{Shortcode.short_code(review.origin_hash)}</span>
                </p>
                <p class="mt-1 text-xs text-gray-500">
                  Author: <span class="font-mono">{Shortcode.short_code(review.author_hash)}</span>
                  | Timestamp: {review.owner_timestamp}
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
