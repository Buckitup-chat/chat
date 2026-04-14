defmodule ChatWeb.ElectricLive.Index do
  @moduledoc """
  Landing page that lists all Electric-synced LiveViews.

  Shows real-time initialization status when the Electric stack is not yet
  ready, then transitions to the resource listing once everything is up.
  """
  use ChatWeb, :live_view

  alias ChatWeb.Plugs.ElectricReadiness

  @poll_interval_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    socket = socket |> assign(:readiness, check_readiness())

    if connected?(socket) do
      Process.send_after(self(), :poll_readiness, @poll_interval_ms)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:poll_readiness, socket) do
    readiness = check_readiness()
    socket = assign(socket, :readiness, readiness)

    Process.send_after(self(), :poll_readiness, @poll_interval_ms)

    {:noreply, socket}
  end

  defp check_readiness do
    case ElectricReadiness.check_readiness() do
      :ready -> :ready
      {:not_ready, phase, _message} -> phase
    end
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

        <.init_status :if={@readiness != :ready} readiness={@readiness} />

        <div :if={@readiness == :ready} class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
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

          <%!-- User Storage --%>
          <a
            href="/electric/user_storage"
            class="block bg-white overflow-hidden shadow rounded-lg hover:shadow-lg transition-shadow duration-200"
          >
            <div class="px-4 py-5 sm:p-6">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <svg
                    class="h-8 w-8 text-purple-600"
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
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">User Storage</dt>
                    <dd class="mt-1 text-lg font-semibold text-gray-900">
                      Encrypted Storage
                    </dd>
                  </dl>
                </div>
              </div>
              <div class="mt-4">
                <p class="text-sm text-gray-600">
                  Real-time encrypted user storage entries (max 10MB per entry).
                </p>
                <p class="mt-2 text-xs text-gray-500 font-mono">
                  /electric/v1/user_storage
                </p>
              </div>
            </div>
          </a>

          <%!-- User Storage Versions --%>
          <a
            href="/electric/user_storage_versions"
            class="block bg-white overflow-hidden shadow rounded-lg hover:shadow-lg transition-shadow duration-200"
          >
            <div class="px-4 py-5 sm:p-6">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <svg
                    class="h-8 w-8 text-indigo-600"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">User Storage Versions</dt>
                    <dd class="mt-1 text-lg font-semibold text-gray-900">
                      Version History
                    </dd>
                  </dl>
                </div>
              </div>
              <div class="mt-4">
                <p class="text-sm text-gray-600">
                  Complete version history of user storage entries with Post-Quantum cryptography.
                </p>
                <p class="mt-2 text-xs text-gray-500 font-mono">
                  /electric/v1/user_storage_version
                </p>
              </div>
            </div>
          </a>

          <%!-- User API Sandbox --%>
          <a
            href="/electric/user_sandbox"
            class="block bg-white overflow-hidden shadow rounded-lg hover:shadow-lg transition-shadow duration-200"
          >
            <div class="px-4 py-5 sm:p-6">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <svg
                    class="h-8 w-8 text-green-600"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
                    />
                  </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">User API Sandbox</dt>
                    <dd class="mt-1 text-lg font-semibold text-gray-900">API Testing</dd>
                  </dl>
                </div>
              </div>
              <div class="mt-4">
                <p class="text-sm text-gray-600">
                  Interactive test client for user_card and user_storage Electric API operations.
                </p>
                <p class="mt-2 text-xs text-gray-500 font-mono">/electric/v1/ingest</p>
              </div>
            </div>
          </a>

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
              <svg class="h-5 w-5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
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

  defp phase_label(phase) do
    case phase do
      "db_initializing" -> "Database initializing..."
      "electric_starting" -> "Electric stack starting..."
      _ -> "Initializing..."
    end
  end

  defp phase_step(phase) do
    case phase do
      "db_initializing" -> 1
      "electric_starting" -> 2
      _ -> 1
    end
  end

  defp step_class(current_step, step) do
    case current_step >= step do
      true -> "flex items-center text-sm font-medium text-blue-600"
      _ -> "flex items-center text-sm font-medium text-gray-400"
    end
  end

  defp step_badge_class(current_step, step) do
    case current_step >= step do
      true ->
        "mr-3 flex-shrink-0 w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs border-blue-600 bg-blue-600 text-white"

      _ ->
        "mr-3 flex-shrink-0 w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs border-gray-300 text-gray-400"
    end
  end

  attr :readiness, :string, required: true

  defp init_status(assigns) do
    ~H"""
    <div class="rounded-lg bg-white shadow p-8 max-w-lg mx-auto mt-8">
      <div class="flex items-center justify-center mb-6">
        <div class="animate-spin rounded-full h-10 w-10 border-b-2 border-blue-600"></div>
      </div>
      <h2 class="text-xl font-semibold text-gray-900 text-center mb-2">System Initializing</h2>
      <p class="text-sm text-gray-500 text-center mb-8">
        {phase_label(@readiness)}
      </p>
      <ol class="space-y-4">
        <li class={step_class(phase_step(@readiness), 1)}>
          <span class={step_badge_class(phase_step(@readiness), 1)}>1</span> Database initializing
        </li>
        <li class={step_class(phase_step(@readiness), 2)}>
          <span class={step_badge_class(phase_step(@readiness), 2)}>2</span> Electric stack starting
        </li>
      </ol>
    </div>
    """
  end
end
