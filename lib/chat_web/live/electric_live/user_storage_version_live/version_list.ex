defmodule ChatWeb.ElectricLive.UserStorageVersionLive.VersionList do
  @moduledoc "Version list renders (grouped and flat) for the user storage version history page."
  use Phoenix.Component

  alias Chat.Proto.Shortcode

  @doc "Versions grouped by storage key (user_hash + uuid)."
  def render_grouped_versions(assigns) do
    ~H"""
    <div class="bg-white shadow overflow-hidden sm:rounded-lg">
      <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
        <h3 class="text-lg leading-6 font-medium text-gray-900">
          Version History (Grouped by Storage Key)
        </h3>
        <p class="mt-1 text-sm text-gray-500">
          Versions are displayed grouped by user_hash and UUID. Use "Show All Versions" to see ungrouped list.
        </p>
      </div>
      <div id="user_storage_versions" phx-update="stream" class="divide-y divide-gray-200">
        <div
          :for={{dom_id, version} <- @streams.user_storage_versions}
          id={dom_id}
          class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
        >
          <div class="mb-2 flex items-center space-x-2">
            <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-purple-100 text-purple-800">
              Key: {version.uuid}
            </span>
            <span class="text-xs text-gray-400 font-mono">
              {Shortcode.short_code(version.user_hash)}
            </span>
          </div>
          {render_version_item(assigns, version)}
        </div>
      </div>
    </div>
    """
  end

  @doc "All versions as one flat list."
  def render_flat_versions(assigns) do
    ~H"""
    <div class="bg-white shadow overflow-hidden sm:rounded-lg">
      <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
        <h3 class="text-lg leading-6 font-medium text-gray-900">All Version History</h3>
      </div>
      <div id="user_storage_versions" phx-update="stream" class="divide-y divide-gray-200">
        <div
          :for={{dom_id, version} <- @streams.user_storage_versions}
          id={dom_id}
          class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
        >
          {render_version_item(assigns, version)}
        </div>
      </div>
    </div>
    """
  end

  @doc "One version row: uuid, hashes, size, timestamp, parent link."
  def render_version_item(assigns, version) do
    assigns = assign(assigns, :version, version)

    ~H"""
    <div class="flex items-start justify-between">
      <div class="flex-1 min-w-0">
        <div class="flex items-center space-x-3">
          <div class="flex-shrink-0">
            <div class="h-10 w-10 rounded-lg bg-purple-600 flex items-center justify-center">
              <svg class="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
            </div>
          </div>
          <div class="flex-1 min-w-0">
            <div>
              <div class="flex items-center space-x-2">
                <p class="text-sm font-medium text-gray-900 font-mono">
                  UUID: {@version.uuid}
                </p>
                <%= if @version.deleted_flag do %>
                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
                    Deleted
                  </span>
                <% end %>
              </div>
              <p class="mt-1 text-xs text-gray-500 font-mono truncate">
                User Hash: {Shortcode.short_code(@version.user_hash)}
              </p>
              <div class="mt-1 flex items-center space-x-4 text-xs text-gray-600">
                <span>Value: {format_bytes(byte_size(@version.value_b64))}</span>
                <span>Timestamp: {format_timestamp(@version.owner_timestamp)}</span>
              </div>
              <%= if @version.parent_sign_hash do %>
                <p class="mt-1 text-xs text-purple-600 font-mono truncate">
                  Parent: {Shortcode.short_code(@version.parent_sign_hash)}
                </p>
              <% else %>
                <p class="mt-1 text-xs text-gray-400 italic">Initial version (no parent)</p>
              <% end %>
              <p class="mt-1 text-xs text-gray-400 font-mono truncate">
                Sign Hash: {Shortcode.short_code(@version.sign_hash)}
              </p>
            </div>
          </div>
        </div>
      </div>
      <div class="ml-5 flex-shrink-0">
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
          Synced
        </span>
      </div>
    </div>
    """
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 2)} KB"

  defp format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 2)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  defp format_timestamp(timestamp) when is_integer(timestamp) do
    now = Chat.TimeKeeper.now_unix()
    diff = now - timestamp

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp format_timestamp(_), do: "unknown"
end
