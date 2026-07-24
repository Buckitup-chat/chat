defmodule ChatWeb.ElectricLive.ReviewsLive.Index do
  @moduledoc "LiveView listing reviews synced via Electric."

  use ChatWeb, :live_view
  import ChatWeb.PhoenixSyncPatch

  alias Chat.Data.Schemas.Review
  alias Chat.Proto.Shortcode

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      endpoint_url = ChatWeb.Endpoint.url() <> "/electric/v1/shapes"
      client = Electric.Client.new!(endpoint: endpoint_url)

      shape =
        Electric.Client.ShapeDefinition.new!("review",
          parser: {Electric.Client.EctoAdapter, Review}
        )

      {:ok,
       socket
       |> Phoenix.LiveView.stream_configure(:reviews, dom_id: &dom_id/1)
       |> sync_stream_fixed(:reviews, shape, client: client)
       |> assign(loading: false, error: nil, connected: true, live: false)}
    else
      {:ok, assign(socket, loading: true, error: nil, connected: false, live: false)}
    end
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
              <h1 class="text-3xl font-bold text-gray-900">Reviews (Electric)</h1>
              <p class="mt-2 text-sm text-gray-600">Real-time reviews synced via Electric</p>
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
            <p class="mt-4 text-sm text-gray-600">Syncing reviews from Electric...</p>
          </div>
        <% else %>
          <div class="bg-white shadow overflow-hidden sm:rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
              <h3 class="text-lg leading-6 font-medium text-gray-900">Reviews Stream</h3>
            </div>
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
                      <span class="font-mono text-xs">{Shortcode.short_code(review.review_hash)}</span>
                      <%= if review.deleted_flag do %>
                        <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
                          Deleted
                        </span>
                      <% end %>
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
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:sync, event}, socket) do
    case event do
      {:reviews, :loaded} ->
        {:noreply, assign(socket, loading: false, error: nil)}

      {:reviews, :live} ->
        {:noreply, assign(socket, live: true, error: nil)}

      {:reviews, {:error, reason}} ->
        {:noreply, assign(socket, loading: false, live: false, error: reason)}

      _ ->
        {:noreply, sync_stream_update(socket, event)}
    end
  end

  # --- Private ---

  defp dom_id(%Review{review_hash: hash}), do: "review-#{hash}"
end
