defmodule ChatWeb.ElectricLive.VouchTokensLive.Index do
  @moduledoc "LiveView listing vouch tokens synced via Electric."

  use ChatWeb.ElectricLive.StreamIndex,
    stream: :vouch_tokens,
    table: "vouch_tokens",
    schema: Chat.Data.Schemas.VouchToken

  defp dom_id(%VouchToken{kind: kind, issuer_hash: ih, subject_hash: sh}) do
    [kind, ih, sh]
    |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
    |> then(&"vt-#{&1}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StreamIndex.page
      title="Vouch Tokens (Electric)"
      subtitle="Real-time signed trust attestations synced via Electric"
      stream_header="Vouch Tokens Stream"
      loading_text="Syncing vouch tokens from Electric..."
      loading={@loading}
      connected={@connected}
      live={@live}
    >
      <:row>
        <div id="vouch_tokens" phx-update="stream" class="divide-y divide-gray-200">
          <div
            :for={{dom_id, vt} <- @streams.vouch_tokens}
            id={dom_id}
            class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
          >
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-gray-900 truncate">
                <span class="font-mono">{vt.kind}</span>
                <span
                  :if={vt.deleted_flag}
                  class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800"
                >
                  Revoked
                </span>
              </p>
              <p class="mt-1 text-xs text-gray-500">
                Issuer: <span class="font-mono">{Shortcode.short_code(vt.issuer_hash)}</span>
                &rarr; Subject: <span class="font-mono">{Shortcode.short_code(vt.subject_hash)}</span>
              </p>
              <p class="mt-1 text-xs text-gray-500">
                Timestamp: {vt.owner_timestamp}
              </p>
            </div>
          </div>
        </div>
      </:row>
    </StreamIndex.page>
    """
  end
end
