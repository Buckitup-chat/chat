defmodule ChatWeb.ElectricLive.VouchSandboxLive.Render do
  @moduledoc false

  use Phoenix.Component

  alias Chat.Proto.Shortcode

  def render_page(assigns) do
    ~H"""
    <div class="x-sandbox min-h-screen bg-gray-50 py-8" id="vouch-sandbox">
      <div class="px-4">
        <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
          &larr; Electric Index
        </a>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Vouch Token Sandbox</h1>
        <p class="text-sm text-gray-600 mb-6">
          View and manage trust attestations via Electric API
        </p>

        <%= if @error_message do %>
          <div class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded flex justify-between">
            <span>{@error_message}</span>
            <button phx-click="clear_error" class="text-red-600 hover:text-red-800">x</button>
          </div>
        <% end %>

        <div class="space-y-6">
          {render_identity_section(assigns)}
          <%= if @identity do %>
            {render_create_section(assigns)}
            {render_tabs(assigns)}
          <% end %>
          {render_log_section(assigns)}
        </div>
      </div>
    </div>
    """
  end

  defp render_identity_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 1: Import Identity</h2>
      <p class="text-sm text-gray-600 mb-3">
        Export keys from
        <a href="/electric/user_sandbox" class="text-blue-600 hover:underline">User Sandbox</a>
        , then import here.
      </p>
      <%= if @identity do %>
        <div class="text-sm">
          <span class="font-medium text-green-700">Identity loaded:</span>
          <span class="font-mono text-xs text-gray-600">
            {Shortcode.short_code(@identity.user_hash)}
          </span>
          <span class="text-gray-500">({@identity.name})</span>
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

  defp render_create_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 2: Create Vouch</h2>
      <form phx-submit="create_vouch" phx-change="form_change" class="space-y-3">
        <div>
          <label class="block text-xs font-medium text-gray-700 mb-1">Subject User</label>
          <select name="subject_hash" required class="w-full px-3 py-2 border rounded-lg text-sm">
            <option value="" disabled selected={@form_subject == ""}>Select a user...</option>
            <option
              :for={u <- @users}
              :if={u.user_hash != @identity.user_hash}
              value={u.user_hash}
              selected={u.user_hash == @form_subject}
            >
              {Shortcode.short_code(u.user_hash)} — {u.name}
            </option>
          </select>
        </div>
        <div>
          <label class="block text-xs font-medium text-gray-700 mb-1">Scope (kind)</label>
          <div class="flex flex-wrap items-end gap-1">
            <div :for={step <- @scope_steps} class="flex items-end gap-1">
              <span :if={step.level > 0} class="text-gray-400 text-lg leading-9">.</span>
              <%= if step.type == :select do %>
                <select name={"scope_#{step.level}"} class="px-3 py-2 border rounded-lg text-sm">
                  <option value="" disabled selected={step.value == ""}>
                    select
                  </option>
                  <option :for={opt <- step.options} value={opt} selected={opt == step.value}>
                    {opt}
                  </option>
                </select>
              <% else %>
                <input
                  type="text"
                  name={"scope_#{step.level}"}
                  value={step.value}
                  placeholder={step.placeholder}
                  class="w-36 px-3 py-2 border rounded-lg text-sm font-mono"
                  phx-debounce="300"
                />
              <% end %>
            </div>
            <div :if={@scope_at_leaf} class="flex items-end gap-1">
              <span class="text-gray-400 text-lg leading-9">.</span>
              <input
                type="text"
                name="scope_extra"
                value={@scope_extra}
                placeholder="narrowing (optional)"
                class="w-44 px-3 py-2 border rounded-lg text-sm font-mono"
                phx-debounce="300"
              />
            </div>
          </div>
          <p class="text-xs text-gray-400 mt-1">
            <%= if @scope_preview != "" do %>
              Kind: <span class="font-mono text-gray-600">{@scope_preview}</span>
            <% else %>
              Dot-path resource scope. Examples: device.&lt;id&gt;.storage.write, origins.&lt;hash&gt;.reviews.write
            <% end %>
          </p>
        </div>
        <div class="flex gap-2">
          <button
            type="submit"
            disabled={@operation_in_progress or @scope_preview == ""}
            class={"px-4 py-2 rounded-lg text-sm text-white #{if @operation_in_progress or @scope_preview == "", do: "bg-gray-400 cursor-not-allowed", else: "bg-green-600 hover:bg-green-700"}"}
          >
            {if @operation_in_progress, do: "Creating...", else: "Create Vouch Token"}
          </button>
          <button
            type="submit"
            name="revoked"
            value="true"
            disabled={@operation_in_progress or @scope_preview == ""}
            title="Publish the token already revoked (deleted_flag: true)"
            class={"t-create-revoked px-4 py-2 rounded-lg text-sm text-white #{if @operation_in_progress or @scope_preview == "", do: "bg-gray-400 cursor-not-allowed", else: "bg-red-600 hover:bg-red-700"}"}
          >
            Create Revoked
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp render_tabs(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <div class="flex items-center justify-between mb-4">
        <div class="flex gap-2">
          <button
            phx-click="switch_tab"
            phx-value-tab="by_me"
            class={"px-3 py-1 rounded text-sm #{if @tab == :by_me, do: "bg-blue-600 text-white", else: "bg-gray-200 text-gray-700 hover:bg-gray-300"}"}
          >
            By me ({length(@vouches_by_me)})
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="for_me"
            class={"px-3 py-1 rounded text-sm #{if @tab == :for_me, do: "bg-blue-600 text-white", else: "bg-gray-200 text-gray-700 hover:bg-gray-300"}"}
          >
            For me ({length(@vouches_for_me)})
          </button>
        </div>
        <button
          phx-click="refresh_vouches"
          class="px-3 py-1 bg-gray-200 text-gray-700 rounded text-sm hover:bg-gray-300"
        >
          Refresh
        </button>
      </div>

      <%= if @tab == :by_me do %>
        {render_vouch_list(assigns, @vouches_by_me, :by_me)}
      <% else %>
        {render_vouch_list(assigns, @vouches_for_me, :for_me)}
      <% end %>
    </div>
    """
  end

  defp render_vouch_list(assigns, vouches, direction) do
    assigns = assign(assigns, vouches: vouches, direction: direction)

    ~H"""
    <%= if @vouches == [] do %>
      <p class="text-sm text-gray-500">No vouch tokens found.</p>
    <% else %>
      <div class="space-y-2">
        <div
          :for={v <- @vouches}
          class={"p-3 rounded border text-sm #{if v.deleted_flag, do: "border-red-200 bg-red-50", else: "border-gray-200"}"}
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0 flex-1">
              <p class={"font-mono text-xs font-medium truncate #{if v.deleted_flag, do: "text-gray-500 line-through", else: "text-gray-900"}"}>
                {v.kind}
              </p>
              <p class="text-xs text-gray-500 mt-1">
                <%= if @direction == :by_me do %>
                  Subject: <span class="font-mono">{Shortcode.short_code(v.subject_hash)}</span>
                <% else %>
                  Issuer: <span class="font-mono">{Shortcode.short_code(v.issuer_hash)}</span>
                <% end %>
              </p>
              <p class="text-xs text-gray-400 mt-0.5">
                Timestamp: {v.owner_timestamp}
                <%= if v.deleted_flag do %>
                  <span class="ml-2 px-1.5 py-0.5 rounded bg-red-100 text-red-700 font-medium">
                    revoked
                  </span>
                <% end %>
              </p>
            </div>
            <%= if @direction == :by_me and not v.deleted_flag do %>
              <button
                phx-click="revoke_vouch"
                phx-value-kind={v.kind}
                phx-value-subject={v.subject_hash}
                phx-value-timestamp={v.owner_timestamp}
                disabled={@operation_in_progress}
                class={"px-3 py-1 rounded text-xs text-white #{if @operation_in_progress, do: "bg-gray-400 cursor-not-allowed", else: "bg-red-600 hover:bg-red-700"}"}
              >
                Revoke
              </button>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp render_log_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Request Log</h2>
      <%= if @request_log == [] do %>
        <p class="text-sm text-gray-500">No requests yet</p>
      <% else %>
        <div class="space-y-3">
          <div
            :for={entry <- @request_log}
            class={"text-xs font-mono p-3 rounded #{if entry.response_status in 200..299, do: "bg-green-50", else: "bg-red-50"}"}
          >
            <p class="font-semibold">{entry.method} {entry.url} -> {entry.response_status}</p>
            <details class="mt-1">
              <summary class="cursor-pointer text-gray-600">Request headers</summary>
              <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(entry.request_headers)}</pre>
            </details>
            <%= if entry.request_body != "" do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Request body</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{entry.request_body}</pre>
              </details>
            <% end %>
            <details class="mt-1">
              <summary class="cursor-pointer text-gray-600">Response headers</summary>
              <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(entry.response_headers)}</pre>
            </details>
            <details class="mt-1">
              <summary class="cursor-pointer text-gray-600">Response body</summary>
              <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{entry.response_body}</pre>
            </details>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_headers(headers) when is_list(headers) do
    Enum.map_join(headers, "\n", fn {k, v} -> "#{k}: #{v}" end)
  end

  defp format_headers(_), do: ""
end
