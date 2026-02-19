defmodule ChatWeb.ElectricLive.Index do
  @moduledoc """
  Landing page that lists all Electric-synced LiveViews.

  This is a static page (no streaming) that provides quick access to all
  available Electric-synced resources in the application.
  """
  use ChatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Electric-Synced LiveViews</h1>
          <p class="mt-2 text-sm text-gray-600">
            Real-time, read-only views powered by Electric sync.
          </p>
        </div>

        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <%!-- User Cards --%>
          <a
            href="/electric/user_cards"
            class="block bg-white overflow-hidden shadow rounded-lg hover:shadow-lg transition-shadow duration-200"
          >
            <div class="px-4 py-5 sm:p-6">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <svg
                    class="h-8 w-8 text-blue-600"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                    />
                  </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">User Cards</dt>
                    <dd class="mt-1 text-lg font-semibold text-gray-900">
                      Post-Quantum Users
                    </dd>
                  </dl>
                </div>
              </div>
              <div class="mt-4">
                <p class="text-sm text-gray-600">
                  Real-time user list with Post-Quantum cryptography support.
                </p>
                <p class="mt-2 text-xs text-gray-500 font-mono">
                  /electric/v1/user_card
                </p>
              </div>
            </div>
          </a>

          <%!-- Placeholder for future Electric-synced views --%>
          <div class="block bg-white overflow-hidden shadow rounded-lg opacity-50">
            <div class="px-4 py-5 sm:p-6">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <svg
                    class="h-8 w-8 text-gray-400"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                    />
                  </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Coming Soon</dt>
                    <dd class="mt-1 text-lg font-semibold text-gray-900">Dialogs & Messages</dd>
                  </dl>
                </div>
              </div>
              <div class="mt-4">
                <p class="text-sm text-gray-600">
                  Real-time messaging streams will be available here.
                </p>
              </div>
            </div>
          </div>

          <div class="block bg-white overflow-hidden shadow rounded-lg opacity-50">
            <div class="px-4 py-5 sm:p-6">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <svg
                    class="h-8 w-8 text-gray-400"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                    />
                  </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Coming Soon</dt>
                    <dd class="mt-1 text-lg font-semibold text-gray-900">Rooms</dd>
                  </dl>
                </div>
              </div>
              <div class="mt-4">
                <p class="text-sm text-gray-600">
                  Real-time room list will be available here.
                </p>
              </div>
            </div>
          </div>
        </div>

        <div class="mt-8 bg-blue-50 border-l-4 border-blue-400 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg
                class="h-5 w-5 text-blue-400"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
            <div class="ml-3">
              <p class="text-sm text-blue-700">
                <strong>About Electric Sync:</strong>
                These views are read-only and automatically update in real-time using Electric
                (PostgreSQL logical replication). Changes made to the database are instantly
                reflected in the UI without manual refreshes.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
