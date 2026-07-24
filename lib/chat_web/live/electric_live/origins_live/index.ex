defmodule ChatWeb.ElectricLive.OriginsLive.Index do
  @moduledoc "LiveView listing all origins synced via Electric."

  use ChatWeb, :live_view
  import ChatWeb.PhoenixSyncPatch

  alias Chat.Data.Schemas.Origin
  alias Chat.Proto.Shortcode

  @impl true
  def mount(_params, _session, socket) do
    case connected?(socket) do
      true ->
        endpoint_url = ChatWeb.Endpoint.url() <> "/electric/v1/shapes"
        client = Electric.Client.new!(endpoint: endpoint_url)

        shape =
          Electric.Client.ShapeDefinition.new!("origins",
            parser: {Electric.Client.EctoAdapter, Origin}
          )

        {:ok,
         socket
         |> Phoenix.LiveView.stream_configure(:origins, dom_id: &dom_id/1)
         |> sync_stream_fixed(:origins, shape, client: client)
         |> assign(loading: false, error: nil, connected: true, live: false)}

      false ->
        {:ok, assign(socket, loading: true, error: nil, connected: false, live: false)}
    end
  end

  defp dom_id(%Origin{origin_hash: hash}), do: "origin-#{Base.encode16(hash, case: :lower)}"

  @impl true
  def handle_info({:sync, {:origins, :loaded}}, socket) do
    {:noreply, assign(socket, loading: false, error: nil)}
  end

  def handle_info({:sync, {:origins, :live}}, socket) do
    {:noreply, assign(socket, live: true, error: nil)}
  end

  def handle_info({:sync, {:origins, {:error, reason}}}, socket) do
    {:noreply, assign(socket, loading: false, live: false, error: reason)}
  end

  def handle_info({:sync, event}, socket) do
    {:noreply, sync_stream_update(socket, event)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="mb-8">
          <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
            &larr; Electric Index
          </a>
          <div class="flex items-center justify-between">
            <div>
              <h1 class="text-3xl font-bold text-gray-900">Origins (Electric)</h1>
              <p class="mt-2 text-sm text-gray-600">
                Real-time origin directory synced via Electric
              </p>
            </div>
            <div class="flex items-center space-x-4">
              <div class="flex items-center space-x-2">
                <span class={"inline-block w-2 h-2 rounded-full #{if @connected, do: "bg-green-500", else: "bg-red-500"}"}>
                </span>
                <span class="text-sm font-medium text-gray-700">
                  {if @connected, do: "Connected", else: "Disconnected"}
                </span>
              </div>
              <%= if @live do %>
                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                  Live
                </span>
              <% end %>
            </div>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex flex-col justify-center items-center py-12">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
            <p class="mt-4 text-sm text-gray-600">Syncing origins from Electric...</p>
          </div>
        <% else %>
          <div class="bg-white shadow overflow-hidden sm:rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
              <h3 class="text-lg leading-6 font-medium text-gray-900">Origins Stream</h3>
            </div>
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
                      <%= if origin.deleted_flag do %>
                        <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
                          Deleted
                        </span>
                      <% end %>
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
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp moderation_badge(:none), do: "bg-gray-100 text-gray-800"
  defp moderation_badge(:post), do: "bg-yellow-100 text-yellow-800"
  defp moderation_badge(:pre), do: "bg-blue-100 text-blue-800"
  defp moderation_badge(_), do: "bg-gray-100 text-gray-800"
end
