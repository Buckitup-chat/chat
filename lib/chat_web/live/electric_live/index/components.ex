defmodule ChatWeb.ElectricLive.Index.Components do
  @moduledoc "Function components of the Electric index: resource cards and init status."
  use Phoenix.Component

  attr :href, :string, required: true
  attr :icon_color, :string, required: true
  attr :icon_path, :string, required: true
  attr :label, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :shapes, :string, required: true
  attr :compact, :boolean, default: false

  def card(assigns) do
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
    if current_step >= step,
      do: "flex items-center text-sm font-medium text-blue-600",
      else: "flex items-center text-sm font-medium text-gray-400"
  end

  defp step_badge_class(current_step, step) do
    if current_step >= step,
      do:
        "mr-3 flex-shrink-0 w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs border-blue-600 bg-blue-600 text-white",
      else:
        "mr-3 flex-shrink-0 w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs border-gray-300 text-gray-400"
  end

  attr :readiness, :string, required: true

  def init_status(assigns) do
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
