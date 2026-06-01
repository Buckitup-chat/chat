defmodule ChatWeb.ElectricLive.UserSandboxLive.Components do
  @moduledoc "Function components for the User Sandbox LiveView."

  use Phoenix.Component

  alias ChatWeb.ElectricLive.UserSandboxLive.Docs

  def docs_sidebar(assigns) do
    ~H"""
    <aside class={"transition-all duration-200 #{if @show_docs, do: "w-80", else: "w-12"} bg-white border-r overflow-y-auto"}>
      <div class="p-2">
        <button
          phx-click="toggle_docs"
          class="w-full flex items-center justify-center p-2 hover:bg-gray-100 rounded"
          title={if @show_docs, do: "Hide docs", else: "Show docs"}
        >
          <span class="text-lg">{if @show_docs, do: "◄", else: "►"}</span>
        </button>
      </div>

      <%= if @show_docs do %>
        <div class="px-4 pb-4">
          <h2 class="text-lg font-semibold mb-4">Documentation</h2>

          <%= for {section_key, section} <- Docs.get_docs() do %>
            <div class="mb-4">
              <button
                phx-click="toggle_doc_section"
                phx-value-section={section_key}
                class="w-full text-left flex items-start gap-2 p-2 hover:bg-gray-50 rounded"
              >
                <span class="text-sm mt-0.5">
                  {if section_key in @expanded_docs, do: "▼", else: "►"}
                </span>
                <span class="font-medium text-gray-900">{section.title}</span>
              </button>

              <%= if section_key in @expanded_docs do %>
                <div class="ml-6 mt-2 text-sm space-y-3">
                  <p class="text-gray-700">{section.description}</p>

                  <div>
                    <h5 class="font-semibold text-gray-900 mb-1">Fields:</h5>
                    <ul class="space-y-1">
                      <%= for field <- section.fields do %>
                        <li class="text-gray-700">
                          <strong class="text-gray-900">{field.name}</strong>
                          <span class="text-gray-500">(<%= field.type %>)</span>: {field.description}
                        </li>
                      <% end %>
                    </ul>
                  </div>

                  <div>
                    <h5 class="font-semibold text-gray-900 mb-1">Example:</h5>
                    <pre class="text-xs bg-gray-100 p-2 rounded overflow-x-auto"><%= section.example %></pre>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </aside>
    """
  end

  def request_log(assigns) do
    ~H"""
    <aside class="w-96 bg-gray-50 border-l overflow-y-auto">
      <div class="p-4">
        <div class="flex justify-between items-center mb-4">
          <h3 class="font-bold text-gray-900">Request Log</h3>
          <%= if length(@request_log) > 0 do %>
            <button phx-click="clear_log" class="text-sm text-gray-600 hover:text-gray-900">
              Clear
            </button>
          <% end %>
        </div>

        <%= if length(@request_log) == 0 do %>
          <p class="text-sm text-gray-500 italic">No requests yet</p>
        <% else %>
          <%= for log_entry <- Enum.reverse(@request_log) do %>
            <div class="mb-4 bg-white p-3 rounded shadow-sm">
              <div class="flex justify-between items-start mb-2">
                <span class="font-mono text-sm font-bold text-gray-900">
                  {log_entry.method} {URI.parse(log_entry.url).path}
                </span>
                <span class={"text-xs px-2 py-1 rounded #{status_color(log_entry.response_status)}"}>
                  {log_entry.response_status}
                </span>
              </div>

              <details class="text-xs">
                <summary class="cursor-pointer text-gray-600 hover:text-gray-900">
                  Request Headers
                </summary>
                <pre class="mt-1 bg-gray-100 p-2 rounded overflow-x-auto"><%= format_headers(log_entry.request_headers) %></pre>
              </details>

              <details class="text-xs mt-1">
                <summary class="cursor-pointer text-gray-600 hover:text-gray-900">
                  Request Body
                </summary>
                <pre class="mt-1 bg-gray-100 p-2 rounded overflow-x-auto"><%= log_entry.request_body %></pre>
              </details>

              <details class="text-xs mt-1">
                <summary class="cursor-pointer text-gray-600 hover:text-gray-900">
                  Response Headers
                </summary>
                <pre class="mt-1 bg-gray-100 p-2 rounded overflow-x-auto"><%= format_headers(log_entry.response_headers) %></pre>
              </details>

              <details class="text-xs mt-1">
                <summary class="cursor-pointer text-gray-600 hover:text-gray-900">
                  Response Body
                </summary>
                <pre class="mt-1 bg-gray-100 p-2 rounded overflow-x-auto"><%= log_entry.response_body %></pre>
              </details>

              <p class="text-xs text-gray-500 mt-2">{format_timestamp(log_entry.timestamp)}</p>
            </div>
          <% end %>
        <% end %>
      </div>
    </aside>
    """
  end

  defp status_color(status) when status >= 200 and status < 300,
    do: "bg-green-100 text-green-800"

  defp status_color(status) when status >= 400, do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_headers(headers) do
    Enum.map_join(headers, "\n", fn {k, v} -> "#{k}: #{v}" end)
  end

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S")
  end

  def user_loaded(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <div class="bg-white shadow rounded-lg p-6">
        <h3 class="text-lg font-bold mb-4">User</h3>

        <div class="mb-4 pl-4 border-l-4 border-blue-500">
          <p class="text-sm text-gray-600">
            Name: <span class="font-mono font-semibold">{@user.name}</span>
          </p>
          <p class="text-xs text-gray-500 font-mono">
            Hash: {short_hash(@user.user_hash_hex)}
          </p>
        </div>

        <div class="mb-6">
          <form phx-submit="update_name" class="flex gap-2 mb-2">
            <input
              type="text"
              name="new_name"
              placeholder="Update name"
              value={@user.name}
              class="flex-1 px-3 py-2 border rounded text-sm"
              disabled={@operation_in_progress}
            />
            <button
              type="submit"
              class="px-4 py-2 bg-blue-500 text-white rounded text-sm hover:bg-blue-600 disabled:bg-gray-400"
              disabled={@operation_in_progress}
            >
              Update
            </button>
          </form>

          <div class="flex gap-2">
            <button
              phx-click="export_keys"
              class="flex-1 px-4 py-2 bg-green-500 text-white rounded text-sm hover:bg-green-600"
              id="export-keys-btn"
            >
              Export Keys
            </button>
            <button
              phx-click="delete_user"
              data-confirm="Delete this user and all storage items?"
              class="flex-1 px-4 py-2 bg-red-500 text-white rounded text-sm hover:bg-red-600 disabled:bg-gray-400"
              disabled={@operation_in_progress}
            >
              Delete User
            </button>
          </div>
        </div>

        <div>
          <h4 class="text-md font-semibold mb-3 text-gray-700">Storage Items</h4>

          <%= if Enum.empty?(@storage_items) do %>
            <p class="text-sm text-gray-400 italic mb-3 pl-4">No storage items</p>
          <% else %>
            <ul class="space-y-1 mb-3">
              <%= for item <- @storage_items do %>
                <li class="flex items-center gap-2 pl-4">
                  <span class="flex-1 font-mono text-sm text-gray-700">
                    {item.uuid}
                    <%= if item.label do %>
                      <span class="text-gray-500 text-xs ml-2">({item.label})</span>
                    <% end %>
                  </span>
                  <button
                    phx-click="view_storage_details"
                    phx-value-uuid={item.uuid}
                    class="px-2 py-1 text-xs text-blue-600 hover:text-blue-800"
                    title="View details"
                  >
                    view
                  </button>
                  <button
                    phx-click="edit_storage"
                    phx-value-uuid={item.uuid}
                    class="px-2 py-1 text-xs text-gray-600 hover:text-gray-800"
                    title="Edit"
                  >
                    edit
                  </button>
                  <button
                    phx-click="delete_storage"
                    phx-value-uuid={item.uuid}
                    data-confirm="Delete this storage item?"
                    class="px-2 py-1 text-xs text-red-600 hover:text-red-800"
                    title="Delete"
                  >
                    delete
                  </button>
                </li>
              <% end %>
            </ul>
          <% end %>

          <button
            phx-click="show_create_storage_form"
            class="px-4 py-2 bg-green-500 text-white rounded text-sm w-full hover:bg-green-600"
            disabled={@operation_in_progress}
          >
            + Create Storage Item
          </button>
        </div>
      </div>
    </div>
    """
  end

  def short_hash(hash_hex), do: String.slice(hash_hex, 0, 16) <> "..."
end
