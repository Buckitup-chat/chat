defmodule ChatWeb.ElectricLive.Index do
  @moduledoc """
  Landing page that lists all Electric-synced LiveViews.

  Shows real-time initialization status when the Electric stack is not yet
  ready, then transitions to the resource listing once everything is up.
  """
  use ChatWeb, :live_view

  alias ChatWeb.Plugs.ElectricReadiness

  @poll_interval_ms 1_000

  @shape_cards [
    %{
      href: "/electric/user_cards",
      icon_color: "text-blue-600",
      icon_path:
        "M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z",
      label: "User Cards",
      title: "Post-Quantum Users",
      shapes: "user_card"
    },
    %{
      href: "/electric/user_storage",
      icon_color: "text-purple-600",
      icon_path:
        "M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4",
      label: "User Storage",
      title: "Encrypted Storage",
      shapes: "user_storage"
    },
    %{
      href: "/electric/user_storage_versions",
      icon_color: "text-indigo-600",
      icon_path: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
      label: "Storage Versions",
      title: "Version History",
      shapes: "user_storage (versions)"
    },
    %{
      href: "/electric/files",
      icon_color: "text-indigo-600",
      icon_path:
        "M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z",
      label: "Files",
      title: "File Manifests",
      shapes: "file"
    },
    %{
      href: "/electric/file_chunks",
      icon_color: "text-purple-600",
      icon_path:
        "M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4",
      label: "File Chunks",
      title: "Chunk Data",
      shapes: "file_chunk"
    },
    %{
      href: "/electric/dialog_keys",
      icon_color: "text-teal-600",
      icon_path:
        "M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z",
      label: "Dialog Keys",
      title: "Key Exchange",
      shapes: "dialog_keys"
    },
    %{
      href: "/electric/dialog_messages",
      icon_color: "text-cyan-600",
      icon_path:
        "M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z",
      label: "Dialog Messages",
      title: "Message Tips",
      shapes: "dialog_messages"
    },
    %{
      href: "/electric/dialog_message_versions",
      icon_color: "text-amber-600",
      icon_path: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
      label: "Message Versions",
      title: "Version History",
      shapes: "dialog_messages (versions)"
    },
    %{
      href: "/electric/dialog_message_reactions",
      icon_color: "text-pink-600",
      icon_path:
        "M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
      label: "Reactions",
      title: "Emoji Reactions",
      shapes: "dialog_message_reactions"
    },
    %{
      href: "/electric/dialog_message_receipts",
      icon_color: "text-emerald-600",
      icon_path: "M5 13l4 4L19 7",
      label: "Receipts",
      title: "Read/Delivered",
      shapes: "dialog_message_receipts"
    },
    %{
      href: "/electric/origins",
      icon_color: "text-orange-600",
      icon_path:
        "M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4",
      label: "Origins",
      title: "Business Entities",
      shapes: "origin"
    },
    %{
      href: "/electric/reviews",
      icon_color: "text-yellow-600",
      icon_path:
        "M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z",
      label: "Reviews",
      title: "Review Records",
      shapes: "review"
    },
    %{
      href: "/electric/review_public_passwords",
      icon_color: "text-yellow-500",
      icon_path:
        "M15 12a3 3 0 11-6 0 3 3 0 016 0z M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z",
      label: "Public Passwords",
      title: "Public Visibility",
      shapes: "review_public_passwords"
    },
    %{
      href: "/electric/review_post_rights",
      icon_color: "text-green-600",
      icon_path:
        "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
      label: "Post Rights",
      title: "Publish Envelopes",
      shapes: "review_post_right"
    },
    %{
      href: "/electric/review_revoke_rights",
      icon_color: "text-red-600",
      icon_path:
        "M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636",
      label: "Revoke Rights",
      title: "Revoke Envelopes",
      shapes: "review_revoke_right"
    },
    %{
      href: "/electric/review_lists",
      icon_color: "text-violet-600",
      icon_path:
        "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01",
      label: "Review Lists",
      title: "Password Lists",
      shapes: "review_list"
    }
  ]

  @sandbox_cards [
    %{
      href: "/electric/user_sandbox",
      icon_color: "text-green-600",
      icon_path: "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4",
      label: "User API Sandbox",
      title: "API Testing",
      shapes: "user_card, user_storage"
    },
    %{
      href: "/file_sandbox.html",
      icon_color: "text-orange-600",
      icon_path:
        "M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12",
      label: "File Sandbox",
      title: "Upload / Download",
      shapes: "file, file_chunk"
    },
    %{
      href: "/electric/dialog_sandbox",
      icon_color: "text-teal-600",
      icon_path:
        "M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z",
      label: "Dialog Sandbox",
      title: "Encrypted Chat",
      shapes: "dialog_keys, dialog_messages"
    },
    %{
      href: "/electric/origin_sandbox",
      icon_color: "text-orange-600",
      icon_path:
        "M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4",
      label: "Origin Sandbox",
      title: "Business Entities",
      shapes: "user_card, origin"
    },
    %{
      href: "/electric/review_sandbox",
      icon_color: "text-yellow-600",
      icon_path:
        "M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z",
      label: "Review Sandbox",
      title: "Review Pipeline",
      shapes: "review, review_list"
    },
    %{
      href: "/electric/origin_reviews",
      icon_color: "text-yellow-600",
      icon_path:
        "M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z",
      label: "Origin Reviews",
      title: "Public Viewer",
      shapes: "origin, review, review_public_passwords"
    }
  ]

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
    assigns =
      assigns |> assign(:shape_cards, @shape_cards) |> assign(:sandbox_cards, @sandbox_cards)

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

  attr :href, :string, required: true
  attr :icon_color, :string, required: true
  attr :icon_path, :string, required: true
  attr :label, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :shapes, :string, required: true
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
          <p :if={!@compact} class="font-semibold text-gray-900 text-lg mt-1">
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
        {@shapes}
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
