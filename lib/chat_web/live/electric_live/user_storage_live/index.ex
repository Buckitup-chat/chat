defmodule ChatWeb.ElectricLive.UserStorageLive.Index do
  @moduledoc """
  LiveView page that displays user storage entries synced via Electric.

  This demonstrates real-time sync of the user_storage table with Post-Quantum
  cryptography support. Uses Electric sync for real-time updates without direct
  database queries.

  Uses a patched version of Phoenix.Sync.LiveView.sync_stream/4 that fixes the nil resume bug.
  The bug exists in phoenix_sync 0.6.1 where it passes `resume: nil` to Electric.Client.stream/2.

  See ChatWeb.PhoenixSyncPatch for the fix.
  """
  use ChatWeb, :live_view
  import ChatWeb.PhoenixSyncPatch

  alias Chat.Data.Schemas.UserStorage

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Use patched Phoenix.Sync to stream user_storage from Electric endpoint
      # This connects to the sync("/user_storage", Chat.Data.Schemas.UserStorage) route
      # Note: UserStorage uses composite primary key (user_hash, uuid)
      {:ok,
       socket
       |> Phoenix.LiveView.stream_configure(:user_storage, dom_id: &dom_id_for_user_storage/1)
       |> sync_stream_fixed(:user_storage, UserStorage)
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

  # Generate DOM ID from composite primary key (user_hash + uuid)
  defp dom_id_for_user_storage(%UserStorage{user_hash: user_hash, uuid: uuid}) do
    "user-storage-#{Base.encode16(user_hash, case: :lower)}-#{uuid}"
  end

  @impl true
  def handle_info({:sync, {:user_storage, :loaded}}, socket) do
    # Initial sync completed - all existing user storage entries loaded
    {:noreply, assign(socket, :loading, false)}
  end

  @impl true
  def handle_info({:sync, {:user_storage, :live}}, socket) do
    # Stream is now live - receiving real-time updates
    {:noreply, assign(socket, :live, true)}
  end

  @impl true
  def handle_info({:sync, event}, socket) do
    # Handle all other sync events (inserts, updates, deletes)
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
                User Storage Stream (LiveView + Electric)
              </h1>
              <p class="mt-2 text-sm text-gray-600">
                Real-time user storage entries with Post-Quantum cryptography support
              </p>
              <p class="mt-1 text-xs text-gray-500 font-mono">
                Using sync("/user_storage", Chat.Data.Schemas.UserStorage) endpoint
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

        <%= if @error do %>
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
        <% end %>

        <%= if @loading do %>
          <div class="flex flex-col justify-center items-center py-12">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
            <p class="mt-4 text-sm text-gray-600">Syncing user storage from Electric...</p>
          </div>
        <% else %>
          <div class="bg-white shadow overflow-hidden sm:rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
              <h3 class="text-lg leading-6 font-medium text-gray-900">User Storage Entries</h3>
            </div>
            <%!-- Use phx-update="stream" for LiveView stream updates --%>
            <div id="user_storage" phx-update="stream" class="divide-y divide-gray-200">
              <div
                :for={{dom_id, storage} <- @streams.user_storage}
                id={dom_id}
                class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150"
              >
                <div class="flex items-start justify-between">
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center space-x-3">
                      <div class="flex-shrink-0">
                        <div class="h-10 w-10 rounded-lg bg-purple-600 flex items-center justify-center">
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
                              d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"
                            />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <div>
                          <p class="text-sm font-medium text-gray-900 font-mono">
                            UUID: {storage.uuid}
                          </p>
                          <p class="mt-1 text-xs text-gray-500 font-mono truncate">
                            User Hash: {Base.encode16(storage.user_hash, case: :lower) |> String.slice(0..31)}...
                          </p>
                          <p class="mt-1 text-xs text-gray-600">
                            Value Size: {format_bytes(byte_size(storage.value))}
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
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Format bytes to human readable size
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 2)} KB"

  defp format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 2)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"
end
