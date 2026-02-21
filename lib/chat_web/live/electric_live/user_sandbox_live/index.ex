defmodule ChatWeb.ElectricLive.UserSandboxLive.Index do
  use ChatWeb, :live_view

  alias ChatWeb.ElectricLive.UserSandboxLive.{ApiClient, Docs}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:user, nil)
      |> assign(:storage_items, [])
      |> assign(:show_storage_form, false)
      |> assign(:editing_storage_uuid, nil)
      |> assign(:viewing_storage_uuid, nil)
      |> assign(:request_log, [])
      |> assign(:show_docs, true)
      |> assign(:expanded_docs, MapSet.new(["user_card"]))
      |> assign(:operation_in_progress, false)
      |> assign(:error_message, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-gray-50">
      <!-- Header -->
      <div class="bg-white border-b px-6 py-4">
        <h1 class="text-2xl font-bold text-gray-900">Electric API Sandbox</h1>
        <p class="text-sm text-gray-600 mt-1">
          Interactive test client for user_card and user_storage Electric API operations
        </p>
      </div>

      <!-- Main Layout -->
      <div class="flex-1 flex overflow-hidden">
        <!-- Left Sidebar (Documentation) -->
        <aside class={"transition-all duration-200 #{if @show_docs, do: "w-80", else: "w-12"} bg-white border-r overflow-y-auto"}>
          <div class="p-2">
            <button
              phx-click="toggle_docs"
              class="w-full flex items-center justify-center p-2 hover:bg-gray-100 rounded"
              title={if @show_docs, do: "Hide docs", else: "Show docs"}
            >
              <span class="text-lg"><%= if @show_docs, do: "◄", else: "►" %></span>
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
                      <%= if section_key in @expanded_docs, do: "▼", else: "►" %>
                    </span>
                    <span class="font-medium text-gray-900"><%= section.title %></span>
                  </button>

                  <%= if section_key in @expanded_docs do %>
                    <div class="ml-6 mt-2 text-sm space-y-3">
                      <p class="text-gray-700"><%= section.description %></p>

                      <div>
                        <h5 class="font-semibold text-gray-900 mb-1">Fields:</h5>
                        <ul class="space-y-1">
                          <%= for field <- section.fields do %>
                            <li class="text-gray-700">
                              <strong class="text-gray-900"><%= field.name %></strong>
                              <span class="text-gray-500">(<%= field.type %>)</span>: <%= field.description %>
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

        <!-- Main Content Area -->
        <main class="flex-1 overflow-y-auto p-6">
          <%= if @error_message do %>
            <div class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded">
              <div class="flex justify-between items-start">
                <div>
                  <strong class="font-semibold">Error:</strong>
                  <span class="block mt-1"><%= @error_message %></span>
                </div>
                <button phx-click="clear_error" class="text-red-600 hover:text-red-800">
                  ✕
                </button>
              </div>
            </div>
          <% end %>

          <%= if @user do %>
            <%= render_user_loaded(assigns) %>
          <% else %>
            <%= render_initial_state(assigns) %>
          <% end %>
        </main>

        <!-- Right Sidebar (Request Log) -->
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
                      <%= log_entry.method %> <%= URI.parse(log_entry.url).path %>
                    </span>
                    <span class={"text-xs px-2 py-1 rounded #{status_color(log_entry.response_status)}"}>
                      <%= log_entry.response_status %>
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

                  <p class="text-xs text-gray-500 mt-2"><%= format_timestamp(log_entry.timestamp) %></p>
                </div>
              <% end %>
            <% end %>
          </div>
        </aside>
      </div>

      <!-- Storage Item Form Modal (shown when creating/editing) -->
      <%= if @show_storage_form do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div class="bg-white rounded-lg shadow-xl p-6 max-w-md w-full">
            <h3 class="text-lg font-bold mb-4">
              <%= if @editing_storage_uuid, do: "Edit Storage Item", else: "Create Storage Item" %>
            </h3>

            <form phx-submit={if @editing_storage_uuid, do: "save_storage_edit", else: "create_storage"}>
              <%= if @editing_storage_uuid do %>
                <input type="hidden" name="uuid" value={@editing_storage_uuid} />
              <% else %>
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    UUID (optional)
                  </label>
                  <input
                    type="text"
                    name="uuid"
                    placeholder="Auto-generated if empty"
                    class="w-full px-3 py-2 border rounded"
                  />
                </div>
              <% end %>

              <div class="mb-4">
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Size (bytes)
                </label>
                <input
                  type="number"
                  name="size"
                  placeholder="256"
                  value={get_storage_item_size(@storage_items, @editing_storage_uuid)}
                  min="1"
                  max="10485760"
                  class="w-full px-3 py-2 border rounded"
                  required
                />
                <p class="text-xs text-gray-500 mt-1">Max: 10MB (10,485,760 bytes)</p>
              </div>

              <div class="mb-4">
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Label (optional)
                </label>
                <input
                  type="text"
                  name="label"
                  placeholder="Description"
                  value={get_storage_item_label(@storage_items, @editing_storage_uuid)}
                  class="w-full px-3 py-2 border rounded"
                />
              </div>

              <p class="text-xs text-gray-500 mb-4">
                <%= if @editing_storage_uuid do %>
                  Will regenerate with new random binary data (base64 encoded)
                <% else %>
                  Creates storage entry with random binary data (base64 encoded)
                <% end %>
              </p>

              <div class="flex gap-2">
                <button
                  type="submit"
                  class="flex-1 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
                  disabled={@operation_in_progress}
                >
                  <%= if @editing_storage_uuid, do: "Save", else: "Create" %>
                </button>
                <button
                  type="button"
                  phx-click="hide_storage_form"
                  class="flex-1 px-4 py-2 bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Storage Details Modal (shown when viewing) -->
      <%= if @viewing_storage_uuid do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div class="bg-white rounded-lg shadow-xl p-6 max-w-2xl w-full">
            <% item = Enum.find(@storage_items, &(&1.uuid == @viewing_storage_uuid)) %>
            <%= if item do %>
              <h3 class="text-lg font-bold mb-4">Storage Item Details</h3>

              <div class="space-y-3 mb-4">
                <div>
                  <label class="text-sm font-medium text-gray-600">UUID:</label>
                  <p class="font-mono text-sm"><%= item.uuid %></p>
                </div>

                <%= if item.label do %>
                  <div>
                    <label class="text-sm font-medium text-gray-600">Label:</label>
                    <p class="text-sm"><%= item.label %></p>
                  </div>
                <% end %>

                <div>
                  <label class="text-sm font-medium text-gray-600">Size:</label>
                  <p class="text-sm font-mono"><%= format_bytes(item.size) %></p>
                </div>

                <div>
                  <label class="text-sm font-medium text-gray-600">Base64 Value:</label>
                  <pre class="mt-1 text-xs bg-gray-100 p-3 rounded overflow-auto max-h-64"><%= item.value_b64 %></pre>
                </div>
              </div>

              <button
                phx-click="hide_storage_details"
                class="w-full px-4 py-2 bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
              >
                Close
              </button>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_initial_state(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-full">
      <div class="text-center">
        <h2 class="text-xl font-semibold text-gray-900 mb-4">
          No user loaded
        </h2>
        <p class="text-gray-600 mb-6">
          Create a test user to begin testing the Electric API
        </p>
        <form phx-submit="create_user" class="space-y-4">
          <input
            type="text"
            name="name"
            placeholder="Enter user name"
            value="Test User"
            class="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            required
            disabled={@operation_in_progress}
          />
          <button
            type="submit"
            disabled={@operation_in_progress}
            class="block w-full bg-blue-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition"
          >
            <%= if @operation_in_progress, do: "Creating...", else: "Create Test User" %>
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp render_user_loaded(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <!-- User Card -->
      <div class="bg-white shadow rounded-lg p-6">
        <h3 class="text-lg font-bold mb-4">User</h3>

        <!-- User Info -->
        <div class="mb-4 pl-4 border-l-4 border-blue-500">
          <p class="text-sm text-gray-600">
            Name: <span class="font-mono font-semibold"><%= @user.name %></span>
          </p>
          <p class="text-xs text-gray-500 font-mono">
            Hash: <%= short_hash(@user.user_hash_hex) %>
          </p>
        </div>

        <!-- User Actions -->
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

          <button
            phx-click="delete_user"
            data-confirm="Delete this user and all storage items?"
            class="px-4 py-2 bg-red-500 text-white rounded text-sm w-full hover:bg-red-600 disabled:bg-gray-400"
            disabled={@operation_in_progress}
          >
            Delete User
          </button>
        </div>

        <!-- Storage Items Section -->
        <div>
          <h4 class="text-md font-semibold mb-3 text-gray-700">Storage Items</h4>

          <%= if Enum.empty?(@storage_items) do %>
            <p class="text-sm text-gray-400 italic mb-3 pl-4">No storage items</p>
          <% else %>
            <ul class="space-y-1 mb-3">
              <%= for item <- @storage_items do %>
                <li class="flex items-center gap-2 pl-4">
                  <span class="flex-1 font-mono text-sm text-gray-700">
                    <%= item.uuid %>
                    <%= if item.label do %>
                      <span class="text-gray-500 text-xs ml-2">(<%= item.label %>)</span>
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

          <!-- Create Storage Item Button -->
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

  # Event Handlers

  @impl true
  def handle_event("create_user", %{"name" => name}, socket) do
    base_url = get_base_url(socket)

    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.create_user(name, base_url) do
      {:ok, %{user: user_data, log_entries: log_entries}} ->
        socket =
          socket
          |> assign(:user, user_data)
          |> assign(:storage_items, [])
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, "Failed to create user: #{reason}")

        {:noreply, socket}
    end
  end

  def handle_event("update_name", %{"new_name" => new_name}, socket) do
    base_url = get_base_url(socket)
    user = socket.assigns.user

    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.update_user_name(user.user_hash, user.sign_skey, new_name, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        updated_user = Map.put(user, :name, new_name)

        socket =
          socket
          |> assign(:user, updated_user)
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, "Failed to update name: #{reason}")

        {:noreply, socket}
    end
  end

  def handle_event("delete_user", _params, socket) do
    base_url = get_base_url(socket)
    user = socket.assigns.user

    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.delete_user(user.user_hash, user.sign_skey, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        socket =
          socket
          |> assign(:user, nil)
          |> assign(:storage_items, [])
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, "Failed to delete user: #{reason}")

        {:noreply, socket}
    end
  end

  def handle_event("show_create_storage_form", _params, socket) do
    {:noreply, assign(socket, show_storage_form: true, editing_storage_uuid: nil)}
  end

  def handle_event("edit_storage", %{"uuid" => uuid}, socket) do
    {:noreply, assign(socket, show_storage_form: true, editing_storage_uuid: uuid)}
  end

  def handle_event("hide_storage_form", _params, socket) do
    {:noreply, assign(socket, show_storage_form: false, editing_storage_uuid: nil)}
  end

  def handle_event("view_storage_details", %{"uuid" => uuid}, socket) do
    {:noreply, assign(socket, viewing_storage_uuid: uuid)}
  end

  def handle_event("hide_storage_details", _params, socket) do
    {:noreply, assign(socket, viewing_storage_uuid: nil)}
  end

  def handle_event("create_storage", params, socket) do
    %{"size" => size_str, "label" => label} = params
    uuid = Map.get(params, "uuid", "")

    base_url = get_base_url(socket)
    user = socket.assigns.user

    # Generate UUID if not provided
    uuid = if uuid == "", do: Ecto.UUID.generate(), else: uuid
    size = String.to_integer(size_str)

    # Generate random binary data and base64 encode it
    value_b64 = generate_storage_value(size)
    # Decode back to binary for API call
    value_binary = Base.decode64!(value_b64)

    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.create_storage(user.user_hash, user.sign_skey, uuid, value_binary, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        new_item = %{
          uuid: uuid,
          value_b64: value_b64,
          size: size,
          label: if(label == "", do: nil, else: label)
        }

        socket =
          socket
          |> update(:storage_items, &[new_item | &1])
          |> assign(:show_storage_form, false)
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, "Failed to create storage: #{reason}")

        {:noreply, socket}
    end
  end

  def handle_event("save_storage_edit", %{"uuid" => uuid, "size" => size_str, "label" => label}, socket) do
    base_url = get_base_url(socket)
    user = socket.assigns.user
    size = String.to_integer(size_str)

    # Generate new random binary data
    value_b64 = generate_storage_value(size)
    value_binary = Base.decode64!(value_b64)

    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.update_storage(user.user_hash, user.sign_skey, uuid, value_binary, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        socket =
          socket
          |> update(:storage_items, fn items ->
            Enum.map(items, fn item ->
              if item.uuid == uuid do
                %{item | value_b64: value_b64, size: size, label: if(label == "", do: nil, else: label)}
              else
                item
              end
            end)
          end)
          |> assign(:show_storage_form, false)
          |> assign(:editing_storage_uuid, nil)
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, "Failed to update storage: #{reason}")

        {:noreply, socket}
    end
  end

  def handle_event("delete_storage", %{"uuid" => uuid}, socket) do
    base_url = get_base_url(socket)
    user = socket.assigns.user

    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.delete_storage(user.user_hash, user.sign_skey, uuid, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        socket =
          socket
          |> update(:storage_items, &Enum.reject(&1, fn item -> item.uuid == uuid end))
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(:operation_in_progress, false)
          |> assign(:error_message, "Failed to delete storage: #{reason}")

        {:noreply, socket}
    end
  end

  def handle_event("toggle_docs", _params, socket) do
    {:noreply, assign(socket, :show_docs, !socket.assigns.show_docs)}
  end

  def handle_event("toggle_doc_section", %{"section" => section}, socket) do
    expanded_docs =
      if section in socket.assigns.expanded_docs do
        MapSet.delete(socket.assigns.expanded_docs, section)
      else
        MapSet.put(socket.assigns.expanded_docs, section)
      end

    {:noreply, assign(socket, :expanded_docs, expanded_docs)}
  end

  def handle_event("clear_log", _params, socket) do
    {:noreply, assign(socket, :request_log, [])}
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  # Helper Functions

  defp short_hash(hash_hex), do: String.slice(hash_hex, 0, 16) <> "..."

  defp status_color(status) when status >= 200 and status < 300,
    do: "bg-green-100 text-green-800"

  defp status_color(status) when status >= 400, do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join("\n")
  end

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S")
  end

  defp get_base_url(socket) do
    uri = socket.host_uri
    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end

  defp format_bytes(bytes) when bytes >= 1024 * 1024 do
    "#{Float.round(bytes / 1024 / 1024, 2)} MB"
  end

  defp format_bytes(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 2)} KB"
  end

  defp format_bytes(bytes), do: "#{bytes} bytes"

  # Generate random binary data and base64 encode it
  defp generate_storage_value(size) do
    :crypto.strong_rand_bytes(size) |> Base.encode64()
  end

  # Helper to get storage item size for form default value
  defp get_storage_item_size(_storage_items, nil), do: "256"

  defp get_storage_item_size(storage_items, uuid) do
    case Enum.find(storage_items, &(&1.uuid == uuid)) do
      nil -> "256"
      item -> to_string(item.size)
    end
  end

  # Helper to get storage item label for form default value
  defp get_storage_item_label(_storage_items, nil), do: ""

  defp get_storage_item_label(storage_items, uuid) do
    case Enum.find(storage_items, &(&1.uuid == uuid)) do
      nil -> ""
      item -> item.label || ""
    end
  end
end
