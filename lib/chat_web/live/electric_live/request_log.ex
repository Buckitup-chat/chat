defmodule ChatWeb.ElectricLive.RequestLog do
  @moduledoc """
  Renders the HTTP request log shared by the electric sandboxes.

  Per the directory `CLAUDE.md`, sandboxes always show full request/response
  detail — headers and bodies each in their own collapsible block.
  """

  use Phoenix.Component

  def render_log_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Request Log</h2>
      <%= if @request_log == [] do %>
        <p class="text-sm text-gray-500">No requests yet</p>
      <% else %>
        <div class="space-y-3">
          <div
            :for={entry <- @request_log}
            class={"text-xs font-mono p-3 rounded #{log_entry_class(entry)}"}
          >
            <p class="font-semibold">{log_entry_label(entry)}</p>
            <%= if entry[:request_headers] do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Request headers</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(entry.request_headers)}</pre>
              </details>
            <% end %>
            <%= if entry[:request_body] && entry.request_body != "" do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Request body</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{entry.request_body}</pre>
              </details>
            <% end %>
            <%= if entry[:response_headers] do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Response headers</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(entry.response_headers)}</pre>
              </details>
            <% end %>
            <%= if entry[:response_body] do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Response body</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{entry.response_body}</pre>
              </details>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp log_entry_label(%{method: method, url: url, response_status: status}),
    do: "#{method} #{url} -> #{status}"

  defp log_entry_label(%{label: label}), do: label

  defp log_entry_class(%{response_status: status}) when status in 200..299, do: "bg-green-50"
  defp log_entry_class(%{response_status: _}), do: "bg-red-50"
  defp log_entry_class(%{status: :ok}), do: "bg-green-50"
  defp log_entry_class(%{status: :error}), do: "bg-red-50"
  defp log_entry_class(_), do: "bg-gray-50"

  defp format_headers(headers) do
    Enum.map_join(headers, "\n", fn {k, v} -> "#{k}: #{v}" end)
  end
end
