defmodule ChatWeb.ElectricLive.DialogMessagesLive.Index do
  use ChatWeb, :live_view
  import ChatWeb.PhoenixSyncPatch

  alias Chat.Data.Schemas.DialogMessage

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> Phoenix.LiveView.stream_configure(:dialog_messages, dom_id: &dom_id/1)
       |> sync_stream_fixed(:dialog_messages, DialogMessage)
       |> assign(:loading, false)
       |> assign(:error, nil)
       |> assign(:connected, true)
       |> assign(:live, false)}
    else
      {:ok,
       socket
       |> assign(:loading, true)
       |> assign(:error, nil)
       |> assign(:connected, false)
       |> assign(:live, false)}
    end
  end

  defp dom_id(%DialogMessage{message_id: mid}) do
    "dm-#{mid}"
  end

  @impl true
  def handle_info({:sync, {:dialog_messages, :loaded}}, socket) do
    {:noreply, assign(socket, loading: false, error: nil)}
  end

  @impl true
  def handle_info({:sync, {:dialog_messages, :live}}, socket) do
    {:noreply, assign(socket, live: true, error: nil)}
  end

  @impl true
  def handle_info({:sync, {:dialog_messages, {:error, reason}}}, socket) do
    {:noreply, assign(socket, loading: false, live: false, error: reason)}
  end

  @impl true
  def handle_info({:sync, event}, socket) do
    {:noreply, sync_stream_update(socket, event)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="mb-8">
          <div class="flex items-center justify-between">
            <div>
              <h1 class="text-3xl font-bold text-gray-900">
                Dialog Messages Stream (LiveView + Electric)
              </h1>
              <p class="mt-2 text-sm text-gray-600">
                Real-time dialog messages (current versions)
              </p>
              <p class="mt-1 text-xs text-gray-500 font-mono">
                Using sync("/dialog_message", Chat.Data.Schemas.DialogMessage) endpoint
              </p>
            </div>
            <.status_indicators connected={@connected} live={@live} />
          </div>
        </div>

        <.error_banner :if={@error} error={@error} />
        <.loading_spinner :if={@loading} label="Syncing dialog messages from Electric..." />

        <div :if={!@loading} class="bg-white shadow overflow-hidden sm:rounded-lg">
          <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
            <h3 class="text-lg leading-6 font-medium text-gray-900">Dialog Messages Stream</h3>
          </div>
          <div id="dialog_messages" phx-update="stream" class="divide-y divide-gray-200">
            <div
              :for={{dom_id, msg} <- @streams.dialog_messages}
              id={dom_id}
              class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
            >
              <div class="flex items-center justify-between">
                <div class="flex items-center min-w-0 flex-1">
                  <div class="flex-shrink-0">
                    <div class="h-12 w-12 rounded-full bg-cyan-600 flex items-center justify-center">
                      <svg
                        class="h-6 w-6 text-white"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z"
                        />
                      </svg>
                    </div>
                  </div>
                  <div class="min-w-0 flex-1 px-4">
                    <p class="text-sm font-medium text-gray-900 font-mono truncate">
                      msg: {msg.message_id}
                      <%= if msg.deleted_flag do %>
                        <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
                          Deleted
                        </span>
                      <% end %>
                    </p>
                    <p class="mt-1 text-sm text-gray-500 font-mono truncate">
                      dialog: {short_hex(msg.dialog_hash)} &middot; sender: {short_hex(
                        msg.sender_hash
                      )}
                    </p>
                    <p class="mt-1 text-xs text-gray-400">
                      Timestamp: {msg.owner_timestamp}
                      <%= if msg.content_b64 do %>
                        &middot; content: {byte_size(msg.content_b64)} bytes
                      <% end %>
                    </p>
                  </div>
                </div>
                <div class="ml-5 flex-shrink-0">
                  <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if msg.deleted_flag, do: "bg-red-100 text-red-800", else: "bg-green-100 text-green-800"}"}>
                    {if msg.deleted_flag, do: "Deleted", else: "Synced"}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp short_hex(nil), do: "nil"

  defp short_hex(bin) when is_binary(bin),
    do: bin |> Base.encode16(case: :lower) |> String.slice(0, 12)

  defp status_indicators(assigns) do
    ~H"""
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
    """
  end

  defp error_banner(assigns) do
    ~H"""
    <div class="mb-4 bg-red-50 border border-red-200 rounded-lg p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
            <path
              fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-red-800">Connection Error</h3>
          <p class="mt-1 text-sm text-red-700">{@error}</p>
        </div>
      </div>
    </div>
    """
  end

  defp loading_spinner(assigns) do
    ~H"""
    <div class="flex flex-col justify-center items-center py-12">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      <p class="mt-4 text-sm text-gray-600">{@label}</p>
    </div>
    """
  end
end
