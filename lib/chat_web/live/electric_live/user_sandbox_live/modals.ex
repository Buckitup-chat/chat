defmodule ChatWeb.ElectricLive.UserSandboxLive.Modals do
  @moduledoc "Modal dialogs for the User Sandbox LiveView."

  use Phoenix.Component

  def storage_form(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-lg shadow-xl p-6 max-w-md w-full">
        <h3 class="text-lg font-bold mb-4">
          {if @editing_storage_uuid, do: "Edit Storage Item", else: "Create Storage Item"}
        </h3>

        <form phx-submit={if @editing_storage_uuid, do: "save_storage_edit", else: "create_storage"}>
          <%= if @editing_storage_uuid do %>
            <input type="hidden" name="uuid" value={@editing_storage_uuid} />
          <% else %>
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-1">UUID (optional)</label>
              <input
                type="text"
                name="uuid"
                placeholder="Auto-generated if empty"
                class="w-full px-3 py-2 border rounded"
              />
            </div>
          <% end %>

          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-1">Size (bytes)</label>
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
            <label class="block text-sm font-medium text-gray-700 mb-1">Label (optional)</label>
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
              {if @editing_storage_uuid, do: "Save", else: "Create"}
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
    """
  end

  defp get_storage_item_size(_storage_items, nil), do: "256"

  defp get_storage_item_size(storage_items, uuid) do
    case Enum.find(storage_items, &(&1.uuid == uuid)) do
      nil -> "256"
      item -> to_string(item.size)
    end
  end

  defp get_storage_item_label(_storage_items, nil), do: ""

  defp get_storage_item_label(storage_items, uuid) do
    case Enum.find(storage_items, &(&1.uuid == uuid)) do
      nil -> ""
      item -> item.label || ""
    end
  end

  def storage_details(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-lg shadow-xl p-6 max-w-2xl w-full">
        <% item = Enum.find(@storage_items, &(&1.uuid == @viewing_storage_uuid)) %>
        <%= if item do %>
          <h3 class="text-lg font-bold mb-4">Storage Item Details</h3>

          <div class="space-y-3 mb-4">
            <div>
              <label class="text-sm font-medium text-gray-600">UUID:</label>
              <p class="font-mono text-sm">{item.uuid}</p>
            </div>

            <%= if item.label do %>
              <div>
                <label class="text-sm font-medium text-gray-600">Label:</label>
                <p class="text-sm">{item.label}</p>
              </div>
            <% end %>

            <div>
              <label class="text-sm font-medium text-gray-600">Size:</label>
              <p class="text-sm font-mono">{format_bytes(item.size)}</p>
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
    """
  end

  defp format_bytes(bytes) when bytes >= 1024 * 1024 do
    "#{Float.round(bytes / 1024 / 1024, 2)} MB"
  end

  defp format_bytes(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 2)} KB"
  end

  defp format_bytes(bytes), do: "#{bytes} bytes"
end
