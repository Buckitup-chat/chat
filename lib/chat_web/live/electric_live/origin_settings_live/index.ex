defmodule ChatWeb.ElectricLive.OriginSettingsLive.Index do
  @moduledoc "LiveView listing all origin settings synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :origin_settings,
    table: "origin_settings",
    schema: Chat.Data.Schemas.OriginSetting

  defp dom_id(%OriginSetting{origin_hash: hash, key: key}) do
    "os-#{Base.encode16(hash, case: :lower)}-#{key}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Origin Settings (Electric)"
      subtitle="Per-origin key-value configuration synced via Electric"
      stream_header="Origin Settings Stream"
      loading_text="Syncing origin settings from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="origin_settings" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, setting} <- @streams.origin_settings}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-gray-900 truncate">
                <span class="font-mono">{setting.key}</span>
                = <span class="font-semibold">{setting.value}</span>
                <span
                  :if={setting.deleted_flag}
                  class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800"
                >
                  Deleted
                </span>
              </p>
              <p class="mt-1 text-xs text-gray-500">
                Origin: <span class="font-mono">{Shortcode.short_code(setting.origin_hash)}</span>
              </p>
              <p class="mt-1 text-xs text-gray-500">
                Timestamp: {setting.owner_timestamp}
              </p>
            </div>
          </div>
        </div>
      </:row>
    </StreamIndex.page>
    """
  end
end
