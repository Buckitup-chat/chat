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

        <div :if={@readiness == :ready} class="flex gap-6 items-start">
          <div class="flex-1 min-w-0">
            <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">
              Shape Lists
            </h2>
            <div class="grid grid-cols-2 lg:grid-cols-3 gap-3">
              <.card
                href="/electric/user_cards"
                icon_color="text-blue-600"
                icon_path="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                label="User Cards"
                title="Post-Quantum Users"
                endpoint="/electric/v1/user_card"
                compact
              />
              <.card
                href="/electric/user_storage"
                icon_color="text-purple-600"
                icon_path="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"
                label="User Storage"
                title="Encrypted Storage"
                endpoint="/electric/v1/user_storage"
                compact
              />
              <.card
                href="/electric/user_storage_versions"
                icon_color="text-indigo-600"
                icon_path="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                label="Storage Versions"
                title="Version History"
                endpoint="/electric/v1/user_storage_version"
                compact
              />
              <.card
                href="/electric/files"
                icon_color="text-indigo-600"
                icon_path="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"
                label="Files"
                title="File Manifests"
                endpoint="/electric/v1/file"
                compact
              />
              <.card
                href="/electric/file_chunks"
                icon_color="text-purple-600"
                icon_path="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4"
                label="File Chunks"
                title="Chunk Data"
                endpoint="/electric/v1/file_chunk"
                compact
              />
            </div>
          </div>

          <div class="w-72 flex-shrink-0">
            <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">
              Sandboxes
            </h2>
            <div class="flex flex-col gap-4">
              <.card
                href="/electric/user_sandbox"
                icon_color="text-green-600"
                icon_path="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
                label="User API Sandbox"
                title="API Testing"
                endpoint="/electric/v1/ingest"
              />
              <.card
                href="/file_sandbox.html"
                icon_color="text-orange-600"
                icon_path="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
                label="File Sandbox"
                title="Upload / Download"
                endpoint="/electric/v1/file, /electric/v1/file_chunk"
              />
              <.card
                href="/electric/dialog_sandbox"
                icon_color="text-teal-600"
                icon_path="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                label="Dialog Sandbox"
                title="Encrypted Chat"
                endpoint="/electric/v1/dialog_key, /electric/v1/dialog_message"
              />
            </div>
          </div>
        </div>

        <div :if={@readiness == :ready} class="mt-8 bg-blue-50 border-l-4 border-blue-400 p-4">
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

  attr :href, :string, required: true
  attr :icon_color, :string, required: true
  attr :icon_path, :string, required: true
  attr :label, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :endpoint, :string, required: true
  attr :compact, :boolean, default: false

  defp card(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "block bg-white overflow-hidden shadow rounded-lg hover:shadow-lg transition-shadow duration-200",
        if(@compact, do: "px-3 py-3", else: "px-4 py-5 sm:p-6")
      ]}
    >
      <div class="flex items-center">
        <svg
          class={["flex-shrink-0", @icon_color, if(@compact, do: "h-6 w-6", else: "h-8 w-8")]}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d={@icon_path} />
        </svg>
        <div class="ml-3 min-w-0">
          <p class={[
            "font-medium text-gray-500 truncate",
            if(@compact, do: "text-xs", else: "text-sm")
          ]}>
            {@label}
          </p>
          <p class={[
            "font-semibold text-gray-900",
            if(@compact, do: "text-sm", else: "text-lg mt-1")
          ]}>
            {@title}
          </p>
        </div>
      </div>
      <div :if={@description} class="mt-3">
        <p class="text-sm text-gray-600">{@description}</p>
      </div>
      <p class={[
        "text-gray-500 font-mono",
        if(@compact, do: "mt-2 text-[10px]", else: "mt-3 text-xs")
      ]}>
        {@endpoint}
      </p>
    </a>
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
