defmodule ChatWeb.ElectricLive.Index do
  @moduledoc """
  Landing page that lists all Electric-synced LiveViews.

  Shows real-time initialization status when the Electric stack is not yet
  ready, then transitions to the resource listing once everything is up.
  """
  use ChatWeb, :live_view

  import ChatWeb.ElectricLive.Index.Components

  alias ChatWeb.ElectricLive.Index.SandboxCards
  alias ChatWeb.ElectricLive.Index.ShapeCards
  alias ChatWeb.Plugs.ElectricReadiness

  @poll_interval_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(readiness: check_readiness())
    |> tap(fn s -> if connected?(s), do: schedule_poll() end)
    |> ok()
  end

  @impl true
  def handle_info(:poll_readiness, socket) do
    socket
    |> assign(readiness: check_readiness())
    |> tap(fn _ -> schedule_poll() end)
    |> noreply()
  end

  defp check_readiness do
    case ElectricReadiness.check_readiness() do
      :ready -> :ready
      {:not_ready, phase, _message} -> phase
    end
  end

  defp schedule_poll, do: Process.send_after(self(), :poll_readiness, @poll_interval_ms)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, shape_cards: ShapeCards.all(), sandbox_cards: SandboxCards.all())

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

        <div :if={@readiness == :ready} class="grid grid-cols-5 gap-6 items-start">
          <div class="col-span-3 min-w-0">
            <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">
              Shape Lists
            </h2>
            <div class="grid grid-cols-2 lg:grid-cols-3 gap-3">
              <.card :for={c <- @shape_cards} {c} compact />
            </div>
          </div>

          <div class="col-span-2">
            <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">
              Sandboxes
            </h2>
            <div class="grid grid-cols-2 gap-4">
              <.card :for={c <- @sandbox_cards} {c} />
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
end
