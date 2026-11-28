defmodule ChatWeb.ElectricLive.DialogSandboxLive.Components.Sidebars do
  @moduledoc false

  use Phoenix.Component

  alias ChatWeb.ElectricLive.DialogSandboxLive.Docs

  def render_docs_sidebar(assigns) do
    ~H"""
    <aside class={"transition-all duration-200 #{if @show_docs, do: "w-80", else: "w-12"} bg-white border-r overflow-y-auto"}>
      <div class="p-2">
        <button
          phx-click="toggle_docs"
          class="w-full flex items-center justify-center p-2 hover:bg-gray-100 rounded"
        >
          <span class="text-lg">{if @show_docs, do: "◄", else: "►"}</span>
        </button>
      </div>
      <%= if @show_docs do %>
        <div class="px-4 pb-4">
          <h2 class="text-lg font-semibold mb-4">Documentation</h2>
          <%= for {key, section} <- Docs.get_docs() do %>
            <div class="mb-4">
              <button
                phx-click="toggle_doc_section"
                phx-value-section={key}
                class="w-full text-left flex items-start gap-2 p-2 hover:bg-gray-50 rounded"
              >
                <span class="text-sm mt-0.5">
                  {if key in @expanded_docs, do: "▼", else: "►"}
                </span>
                <span class="font-medium text-gray-900">{section.title}</span>
              </button>
              <%= if key in @expanded_docs do %>
                <div class="ml-6 mt-2 text-sm space-y-2">
                  <p class="text-gray-700">{section.description}</p>
                  <ul class="space-y-1">
                    <%= for field <- section.fields do %>
                      <li class="text-gray-700">
                        <strong>{field.name}</strong>
                        <span class="text-gray-500">({field.type})</span> : {field.description}
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </aside>
    """
  end

  def render_request_log(assigns) do
    ~H"""
    <aside class={"transition-all duration-200 #{if @show_log, do: "w-96", else: "w-12"} bg-gray-50 border-l overflow-y-auto"}>
      <div class="p-2">
        <button
          phx-click="toggle_log"
          class="w-full flex items-center justify-center p-2 hover:bg-gray-100 rounded"
          title={if @show_log, do: "Hide log", else: "Show log"}
        >
          <span class="text-lg">{if @show_log, do: "►", else: "◄"}</span>
        </button>
      </div>
      <%= if @show_log do %>
        <div class="px-4 pb-4">
          <div class="flex justify-between items-center mb-4">
            <h3 class="font-bold text-gray-900">Request Log</h3>
            <button phx-click="clear_log" class="text-sm text-gray-600 hover:text-gray-900">
              Clear
            </button>
          </div>
          <%= if @request_log == [] do %>
            <p class="text-sm text-gray-500 italic">No requests yet</p>
          <% else %>
            <div class="space-y-2">
              <%= for log <- Enum.reverse(@request_log) do %>
                <% uri = URI.parse(log.url) %>
                <% params = if uri.query, do: URI.decode_query(uri.query), else: %{} %>
                <div class="bg-white p-3 rounded shadow-sm text-xs">
                  <div class="flex justify-between items-center mb-1">
                    <span class="font-mono font-bold">
                      {log.method} {uri.path}
                    </span>
                    <span class={"px-2 py-0.5 rounded #{status_color(log.response_status)}"}>
                      {log.response_status}
                    </span>
                  </div>
                  <%= if params != %{} do %>
                    <div class="mt-1 space-y-0.5">
                      <%= for {k, v} <- params do %>
                        <div class="flex gap-1">
                          <span class="font-mono text-gray-500">{k}:</span>
                          <span class="font-mono text-gray-800 break-all">{v}</span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  <%= if log.request_body != "" do %>
                    <details class="mt-1">
                      <summary class="text-gray-500 cursor-pointer">Request body</summary>
                      <pre class="mt-1 bg-yellow-50 p-2 rounded overflow-x-auto max-h-40 overflow-y-auto whitespace-pre-wrap break-all">{log.request_body}</pre>
                    </details>
                  <% end %>
                  <details class="mt-1">
                    <summary class="text-gray-500 cursor-pointer">Response headers</summary>
                    <div class="mt-1 bg-gray-100 p-2 rounded max-h-40 overflow-y-auto">
                      <%= for {k, v} <- format_resp_headers(log.response_headers) do %>
                        <div class="flex gap-1">
                          <span class="font-mono text-gray-500">{k}:</span>
                          <span class="font-mono text-gray-800 break-all">{v}</span>
                        </div>
                      <% end %>
                    </div>
                  </details>
                  <details class="mt-1">
                    <summary class="text-gray-500 cursor-pointer">Response body</summary>
                    <pre class="mt-1 bg-gray-100 p-2 rounded overflow-x-auto max-h-40 overflow-y-auto whitespace-pre-wrap break-all">{log.response_body}</pre>
                  </details>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </aside>
    """
  end

  defp format_resp_headers(headers) when is_map(headers) do
    Enum.flat_map(headers, fn {k, vs} ->
      Enum.map(List.wrap(vs), &{k, &1})
    end)
  end

  defp format_resp_headers(headers) when is_list(headers), do: headers
  defp format_resp_headers(_), do: []

  defp status_color(s) when s >= 200 and s < 300, do: "bg-green-100 text-green-800"
  defp status_color(s) when s >= 400, do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end
