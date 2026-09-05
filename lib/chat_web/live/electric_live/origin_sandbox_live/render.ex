defmodule ChatWeb.ElectricLive.OriginSandboxLive.Render do
  @moduledoc false

  use Phoenix.Component

  alias Chat.Proto.Shortcode

  def render_page(assigns) do
    ~H"""
    <div class="x-sandbox min-h-screen bg-gray-50 py-8" id="origin-owner-sandbox" phx-hook="DownloadFile">
      <div class="px-4">
        <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
          &larr; Electric Index
        </a>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Origin Owner Sandbox</h1>
        <p class="text-sm text-gray-600 mb-6">
          Test origin ownership operations via Electric API
        </p>

        <%= if @error_message do %>
          <div class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded flex justify-between">
            <span>{@error_message}</span>
            <button phx-click="clear_error" class="text-red-600 hover:text-red-800">x</button>
          </div>
        <% end %>

        <div class="space-y-6">
          {render_owner_section(assigns)}
          <%= if @owner do %>
            {render_origins_section(assigns)}
          <% end %>
          <%= if @origin do %>
            {render_operations_section(assigns)}
          <% end %>
          {render_log_section(assigns)}
        </div>
      </div>
    </div>
    """
  end

  defp render_owner_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 1: Import Owner</h2>
      <p class="text-sm text-gray-600 mb-3">
        Export keys from
        <a href="/electric/user_sandbox" class="text-blue-600 hover:underline">User Sandbox</a>
        , then import here.
      </p>
      <%= if @owner do %>
        <div class="text-sm">
          <span class="font-medium text-green-700">Identity loaded:</span>
          <span class="font-mono text-xs text-gray-600">{Shortcode.short_code(@owner.user_hash)}</span>
          <span class="text-gray-500">({@owner.name})</span>
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

  defp render_origins_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <div class="flex justify-between items-center mb-4">
        <h2 class="text-lg font-semibold text-gray-900">Step 2: Origins</h2>
        <button
          phx-click="refresh_origins"
          class="px-3 py-1 bg-gray-200 text-gray-700 rounded text-sm hover:bg-gray-300"
        >
          Refresh
        </button>
      </div>
      <%= if @origins != [] do %>
        <div class="space-y-2 mb-4">
          <div
            :for={o <- @origins}
            class={"flex items-center justify-between p-3 rounded border #{if @origin && @origin.origin_hash == o.origin_hash, do: "border-blue-500 bg-blue-50", else: "border-gray-200"}"}
          >
            <div class="text-sm">
              <span class="font-medium">{o.name}</span>
              <span class="text-gray-500 ml-2">({o.moderation_mode})</span>
              <%= if o.deleted_flag do %>
                <span class="text-red-500 ml-2">[deleted]</span>
              <% end %>
            </div>
            <button
              phx-click="select_origin"
              phx-value-hash={o.origin_hash}
              class={"px-3 py-1 rounded text-sm text-white #{if @origin && @origin.origin_hash == o.origin_hash, do: "bg-blue-400", else: "bg-blue-600 hover:bg-blue-700"}"}
            >
              {if @origin && @origin.origin_hash == o.origin_hash, do: "Selected", else: "Select"}
            </button>
          </div>
        </div>
      <% else %>
        <p class="text-sm text-gray-500 mb-4">No origins found for this owner.</p>
      <% end %>
      <details class="mt-2">
        <summary class="cursor-pointer text-sm font-medium text-gray-700">
          Create New Origin
        </summary>
        <form phx-submit="create_origin" class="flex gap-3 items-end mt-3">
          <div class="flex-1">
            <label class="block text-xs font-medium text-gray-700 mb-1">Origin name</label>
            <input
              type="text"
              name="name"
              value="Test Coffee Shop"
              required
              class="w-full px-3 py-2 border rounded-lg text-sm"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Moderation</label>
            <select name="moderation" class="px-3 py-2 border rounded-lg text-sm">
              <option value="none">none</option>
              <option value="post">post</option>
              <option value="pre">pre</option>
            </select>
          </div>
          <button
            type="submit"
            class="bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700 text-sm"
          >
            Create
          </button>
        </form>
      </details>
    </div>
    """
  end

  defp render_operations_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-2">Step 3: Owner Operations</h2>
      <div class="text-sm mb-3 space-y-1">
        <p><span class="font-medium">Name:</span> {@origin.name}</p>
        <p class="font-mono text-xs text-gray-500 truncate">
          <span class="font-medium font-sans">Hash:</span> {Shortcode.short_code(@origin.origin_hash)}
        </p>
        <p><span class="font-medium">Moderation:</span> {@origin.moderation_mode}</p>
        <p><span class="font-medium">Deleted:</span> {to_string(@origin.deleted_flag)}</p>
        <p><span class="font-medium">Timestamp:</span> {@origin.owner_timestamp}</p>
      </div>
      <%= if @origin[:origin_sign_skey] do %>
        <button
          phx-click="export_origin_identity"
          class="mb-4 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 text-sm"
        >
          Export Origin Identity
        </button>
      <% end %>
      <div class="mb-4 flex items-center gap-3">
        <button
          phx-click="refresh_pending_reviews"
          class="px-3 py-1 bg-gray-200 text-gray-700 rounded text-sm hover:bg-gray-300"
        >
          Check queue
        </button>
        {render_pending_status(assigns)}
      </div>
      <div class="space-y-4">
        <div class="border-b pb-4">
          <h3 class="text-sm font-semibold text-gray-700 mb-2">Update</h3>
          <form phx-submit="update_origin" class="flex gap-3 items-end">
            <div class="flex-1">
              <label class="block text-xs font-medium text-gray-700 mb-1">New name</label>
              <input
                type="text"
                name="name"
                value={@origin.name}
                required
                disabled={@pending_reviews != false}
                class="w-full px-3 py-2 border rounded-lg text-sm disabled:bg-gray-100"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-700 mb-1">Moderation</label>
              <select
                name="moderation"
                disabled={@pending_reviews != false}
                class="px-3 py-2 border rounded-lg text-sm disabled:bg-gray-100"
              >
                <option value="none" selected={@origin.moderation_mode == "none"}>none</option>
                <option value="post" selected={@origin.moderation_mode == "post"}>post</option>
                <option value="pre" selected={@origin.moderation_mode == "pre"}>pre</option>
              </select>
            </div>
            <button
              type="submit"
              disabled={@pending_reviews != false}
              class={"px-4 py-2 rounded-lg text-sm text-white #{if @pending_reviews != false, do: "bg-gray-400 cursor-not-allowed", else: "bg-yellow-600 hover:bg-yellow-700"}"}
            >
              Update
            </button>
          </form>
        </div>
        <div>
          <h3 class="text-sm font-semibold text-gray-700 mb-2">Delete</h3>
          <button
            phx-click="delete_origin"
            disabled={@pending_reviews != false or @origin.deleted_flag}
            class={"px-4 py-2 rounded-lg text-sm text-white #{if @pending_reviews != false or @origin.deleted_flag, do: "bg-gray-400 cursor-not-allowed", else: "bg-red-600 hover:bg-red-700"}"}
          >
            {cond do
              @origin.deleted_flag -> "Deleted"
              @pending_reviews != false -> "Delete (blocked)"
              true -> "Delete Origin"
            end}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp render_pending_status(assigns) do
    ~H"""
    <%= case @pending_reviews do %>
      <% nil -> %>
        <span class="text-sm text-gray-500">Queue not checked yet</span>
      <% true -> %>
        <span class="text-sm text-amber-700 font-medium">
          Reviews pending — operations blocked
        </span>
      <% false -> %>
        <span class="text-sm text-green-700 font-medium">No pending reviews</span>
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
