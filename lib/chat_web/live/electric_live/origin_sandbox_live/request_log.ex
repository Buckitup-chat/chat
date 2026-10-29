defmodule ChatWeb.ElectricLive.OriginSandboxLive.RequestLog do
  @moduledoc false

  use Phoenix.Component

  attr :log, :list, required: true

  def render_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Request Log</h2>
      <%= if @log == [] do %>
        <p class="text-sm text-gray-500">No requests yet</p>
      <% else %>
        <div class="space-y-3">
          <.log_entry :for={entry <- @log} entry={entry} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :entry, :map, required: true

  defp log_entry(assigns) do
    ~H"""
    <div class={"text-xs font-mono p-3 rounded #{if @entry.response_status in 200..299, do: "bg-green-50", else: "bg-red-50"}"}>
      <p class="font-semibold">{@entry.method} {@entry.url} -> {@entry.response_status}</p>
      <details class="mt-1">
        <summary class="cursor-pointer text-gray-600">Request headers</summary>
        <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(@entry.request_headers)}</pre>
      </details>
      <details :if={@entry.request_body != ""} class="mt-1">
        <summary class="cursor-pointer text-gray-600">Request body</summary>
        <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{@entry.request_body}</pre>
      </details>
      <details class="mt-1">
        <summary class="cursor-pointer text-gray-600">Response headers</summary>
        <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(@entry.response_headers)}</pre>
      </details>
      <details class="mt-1">
        <summary class="cursor-pointer text-gray-600">Response body</summary>
        <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{@entry.response_body}</pre>
      </details>
    </div>
    """
  end

  defp format_headers(headers) when is_list(headers) do
    Enum.map_join(headers, "\n", fn {k, v} -> "#{k}: #{v}" end)
  end

  defp format_headers(_), do: ""
end
