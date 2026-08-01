defmodule ChatWeb.ElectricLive.ReviewListsLive.Index do
  @moduledoc "LiveView listing review lists synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :records,
    table: "review_list",
    schema: Chat.Data.Schemas.ReviewList

  defp dom_id(%ReviewList{user_hash: uh, review_hash: rh}),
    do: "rl-#{Shortcode.short_code(uh)}-#{Shortcode.short_code(rh)}"

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Review Lists (Electric)"
      subtitle="Per-user encrypted lists of review passwords"
      stream_header="Review Lists Stream"
      loading_text="Syncing review lists from Electric..."
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
                  User:
                  <span class="font-mono text-xs">{Shortcode.short_code(record.user_hash)}</span>
                  | Review:
                  <span class="font-mono text-xs">
                    {Shortcode.short_code(record.review_hash)}
                  </span>
                  | Origin:
                  <span class="font-mono text-xs">
                    {Shortcode.short_code(record.origin_hash)}
                  </span>
                  <span
                    :if={record.deleted_flag}
                    class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800"
                  >
                    Deleted
                  </span>
                </p>
                <p class="mt-1 text-xs text-gray-500">
                  Password Sign:
                  <span class="font-mono">
                    {Shortcode.short_code(record.review_password_sign_hash)}
                  </span>
                  | Post Right:
                  <span class="font-mono">
                    {Shortcode.short_code(record.post_right_sign_hash)}
                  </span>
                  | Revoke Right:
                  <span class="font-mono">
                    {Shortcode.short_code(record.revoke_right_sign_hash)}
                  </span>
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
