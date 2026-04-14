defmodule ChatWeb.ElectricLive.UserStorageVersionLive.Index do
  @moduledoc """
  LiveView page that displays user storage version history synced via Electric.

  This shows the complete version history of user_storage entries with Post-Quantum
  cryptography support. Uses Electric sync for real-time updates without direct
  database queries.

  Uses a patched version of Phoenix.Sync.LiveView.sync_stream/4 that fixes the nil resume bug.
  The bug exists in phoenix_sync 0.6.1 where it passes `resume: nil` to Electric.Client.stream/2.

  See ChatWeb.PhoenixSyncPatch for the fix.
  """
  use ChatWeb, :live_view
  import ChatWeb.PhoenixSyncPatch

  alias Chat.Data.Schemas.UserStorageVersion

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> Phoenix.LiveView.stream_configure(:user_storage_versions,
         dom_id: &dom_id_for_user_storage_version/1
       )
       |> sync_stream_fixed(:user_storage_versions, UserStorageVersion)
       |> assign(:loading, false)
       |> assign(:error, nil)
       |> assign(:connected, true)
       |> assign(:live, false)
       |> assign(:group_by_key, true)}
    else
      {:ok,
       socket
       |> assign(:loading, true)
       |> assign(:error, nil)
       |> assign(:connected, false)
       |> assign(:live, false)
       |> assign(:group_by_key, true)}
    end
  end

  defp dom_id_for_user_storage_version(%UserStorageVersion{
         user_hash: user_hash,
         uuid: uuid,
         sign_hash: sign_hash
       }) do
    "user-storage-version-#{Base.encode16(user_hash, case: :lower)}-#{uuid}-#{Base.encode16(sign_hash, case: :lower)}"
  end

  @impl true
  def handle_info({:sync, {:user_storage_versions, :loaded}}, socket) do
    {:noreply, assign(socket, loading: false, error: nil)}
  end

  @impl true
  def handle_info({:sync, {:user_storage_versions, :live}}, socket) do
    {:noreply, assign(socket, live: true, error: nil)}
  end

  @impl true
  def handle_info({:sync, {:user_storage_versions, {:error, reason}}}, socket) do
    {:noreply, assign(socket, loading: false, live: false, error: reason)}
  end

  @impl true
  def handle_info({:sync, event}, socket) do
    {:noreply, sync_stream_update(socket, event)}
  end

  @impl true
  def handle_event("toggle_grouping", _params, socket) do
    {:noreply, assign(socket, :group_by_key, !socket.assigns.group_by_key)}
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
                User Storage Version History (LiveView + Electric)
              </h1>
              <p class="mt-2 text-sm text-gray-600">
                Complete version history of user storage entries with Post-Quantum cryptography
              </p>
              <p class="mt-1 text-xs text-gray-500 font-mono">
                Using sync("/user_storage_version", Chat.Data.Schemas.UserStorageVersion) endpoint
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

        <div class="mb-4 flex justify-end">
          <button
            phx-click="toggle_grouping"
            class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500"
          >
            <%= if @group_by_key do %>
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 6h16M4 12h16M4 18h16"
                />
              </svg>
              Show All Versions
            <% else %>
              <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                />
              </svg>
              Group by Storage Key
            <% end %>
          </button>
        </div>

        <%= if @loading do %>
          <div class="flex flex-col justify-center items-center py-12">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-purple-600"></div>
            <p class="mt-4 text-sm text-gray-600">Syncing version history from Electric...</p>
          </div>
        <% else %>
          <%= if @group_by_key do %>
            {render_grouped_versions(assigns)}
          <% else %>
            {render_flat_versions(assigns)}
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_grouped_versions(assigns) do
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
              {Base.encode16(version.user_hash, case: :lower) |> String.slice(0..15)}...
            </span>
          </div>
          {render_version_item(assigns, version)}
        </div>
      </div>
    </div>
    """
  end

  defp render_flat_versions(assigns) do
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

  defp render_version_item(assigns, version) do
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
                User Hash: {Base.encode16(@version.user_hash, case: :lower) |> String.slice(0..31)}...
              </p>
              <div class="mt-1 flex items-center space-x-4 text-xs text-gray-600">
                <span>Value: {format_bytes(byte_size(@version.value_b64))}</span>
                <span>Timestamp: {format_timestamp(@version.owner_timestamp)}</span>
              </div>
              <%= if @version.parent_sign_hash do %>
                <p class="mt-1 text-xs text-purple-600 font-mono truncate">
                  Parent: {Base.encode16(@version.parent_sign_hash, case: :lower)
                  |> String.slice(0..15)}...
                </p>
              <% else %>
                <p class="mt-1 text-xs text-gray-400 italic">Initial version (no parent)</p>
              <% end %>
              <p class="mt-1 text-xs text-gray-400 font-mono truncate">
                Sign Hash: {Base.encode16(@version.sign_hash, case: :lower) |> String.slice(0..15)}...
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
    now = System.system_time(:second)
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
