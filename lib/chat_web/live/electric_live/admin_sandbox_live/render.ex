defmodule ChatWeb.ElectricLive.AdminSandboxLive.Render do
  @moduledoc false

  use Phoenix.Component

  alias Chat.Proto.Shortcode

  @gate_modes [:open, :guarded, :trust]

  def render_page(assigns) do
    ~H"""
    <div class="x-sandbox min-h-screen bg-gray-50 py-8" id="admin-sandbox">
      <div class="max-w-2xl mx-auto px-4">
        <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
          &larr; Electric Index
        </a>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Admin Sandbox</h1>
        <p class="text-sm text-gray-600 mb-6">
          Device identity and access gate configuration
        </p>

        <%= if @error_message do %>
          <div class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded flex justify-between">
            <span>{@error_message}</span>
            <button phx-click="clear_error" class="text-red-600 hover:text-red-800">x</button>
          </div>
        <% end %>

        <div class="space-y-6">
          {render_device_section(assigns)}
          {render_identity_section(assigns)}
          {render_gate_section(assigns)}
        </div>
      </div>
    </div>
    """
  end

  defp render_device_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Device Identity</h2>
      <dl class="space-y-3">
        <div>
          <dt class="text-xs font-medium text-gray-500 uppercase tracking-wide">Device ID</dt>
          <dd class="mt-1 font-mono text-sm text-gray-900">{@device_id}</dd>
        </div>
        <div>
          <dt class="text-xs font-medium text-gray-500 uppercase tracking-wide">
            Server PQ User Hash
          </dt>
          <dd class="mt-1 font-mono text-sm text-gray-900">
            {if @server_user_hash, do: Shortcode.short_code(@server_user_hash), else: "not initialized"}
          </dd>
        </div>
        <div>
          <dt class="text-xs font-medium text-gray-500 uppercase tracking-wide">
            Admin (Owner) User Hash
          </dt>
          <dd class="mt-1 font-mono text-sm text-gray-900">
            {if @admin_user_hash, do: Shortcode.short_code(@admin_user_hash), else: "not captured"}
          </dd>
        </div>
      </dl>
    </div>
    """
  end

  defp render_identity_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Admin Authentication</h2>
      <p class="text-sm text-gray-600 mb-3">
        Import admin keys to manage the access gate. Export from
        <a href="/electric/user_sandbox" class="text-blue-600 hover:underline">User Sandbox</a>.
      </p>
      <%= if @identity do %>
        <div class="text-sm space-y-1">
          <p>
            <span class="font-medium text-gray-700">Identity:</span>
            <span class="font-mono text-xs text-gray-600">
              {Shortcode.short_code(@identity.user_hash)}
            </span>
            <span class="text-gray-500">({@identity.name})</span>
          </p>
          <p :if={@is_admin} class="text-green-700 font-medium">Admin verified</p>
          <p :if={!@is_admin} class="text-amber-700 font-medium">
            Not admin — gate controls are read-only
          </p>
        </div>
      <% else %>
        <form phx-change="validate_key_file" phx-submit="import_keys" class="flex items-center gap-4">
          <.live_file_input upload={@uploads.key_file} class="text-sm" />
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 text-sm"
          >
            Import Keys
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  defp render_gate_section(assigns) do
    assigns = assign(assigns, gate_modes: @gate_modes)

    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Access Gate</h2>
      <p class="text-sm text-gray-600 mb-4">
        Controls who can read and write data through the Electric API.
      </p>

      <div class="space-y-3">
        <div
          :for={mode <- @gate_modes}
          class={[
            "border rounded-lg p-4 transition-colors",
            if(mode == @gate_mode,
              do: "border-blue-500 bg-blue-50",
              else: "border-gray-200"
            ),
            if(@is_admin and mode != @gate_mode,
              do: "cursor-pointer hover:border-gray-300",
              else: ""
            )
          ]}
          phx-click={if(@is_admin, do: "set_gate_mode")}
          phx-value-mode={if(@is_admin, do: mode)}
        >
          <div class="flex items-center justify-between">
            <div>
              <span class={[
                "font-semibold text-sm",
                if(mode == @gate_mode, do: "text-blue-700", else: "text-gray-900")
              ]}>
                {mode}
              </span>
              <p class="text-xs text-gray-500 mt-1">{mode_description(mode)}</p>
            </div>
            <div :if={mode == @gate_mode} class="text-blue-600">
              <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
          </div>
        </div>
      </div>

      <p :if={!@is_admin} class="mt-3 text-xs text-gray-400">
        Import admin identity above to change the gate mode.
      </p>
    </div>
    """
  end

  defp mode_description(:open), do: "Anyone with valid PoP can read and write. No chain checks."
  defp mode_description(:guarded), do: "Writes are chain-gated; reads open to anyone with valid PoP."
  defp mode_description(:trust), do: "All access — reads and writes — gated by PoP + vouch chain."
end
