defmodule ChatWeb.ElectricLive.DialogSandboxLive.Components do
  @moduledoc false

  use Phoenix.Component

  alias ChatWeb.ElectricLive.DialogSandboxLive.Docs

  def render_error(assigns) do
    ~H"""
    <%= if @error_message do %>
      <div class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded flex justify-between">
        <span>{@error_message}</span>
        <button phx-click="clear_error" class="text-red-600 hover:text-red-800 font-bold">
          &times;
        </button>
      </div>
    <% end %>
    """
  end

  def render_identity_section(assigns) do
    ~H"""
    <section class="bg-white shadow rounded-lg p-6 mb-6">
      <h3 class="text-lg font-bold mb-4">1. Import Identity</h3>
      <p class="text-sm text-gray-600 mb-3">
        Export keys from
        <a href="/electric/user_sandbox" class="text-blue-600 hover:underline">User Sandbox</a>
        , then import here.
      </p>
      <form phx-change="validate_key_file" phx-submit="import_keys" class="flex items-center gap-4">
        <.live_file_input upload={@uploads.key_file} class="text-sm" />
        <button
          type="submit"
          class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 text-sm font-medium"
        >
          Import Keys
        </button>
      </form>
      <%= if @user do %>
        <div class="mt-3 text-sm">
          <span class="font-medium text-green-700">Identity loaded:</span>
          <span class="font-mono text-gray-600">{short_hash(@user.user_hash)}</span>
          <span class="text-gray-500">({@user.name})</span>
        </div>
      <% end %>
    </section>
    """
  end

  def render_dialogs_section(assigns) do
    ~H"""
    <section class="bg-white shadow rounded-lg p-6 mb-6">
      <div class="flex justify-between items-center mb-4">
        <h3 class="text-lg font-bold">2. Dialogs</h3>
        <button
          phx-click="fetch_dialogs"
          class="px-3 py-1 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 text-sm"
        >
          Refresh
        </button>
      </div>

      <form phx-change="select_peer" phx-submit="create_dialog" class="mb-4 flex gap-2">
        <select name="peer_hash" class="flex-1 px-3 py-2 border rounded text-sm">
          <option value="">Select a peer...</option>
          <%= for peer <- @available_peers do %>
            <option value={peer.user_hash} selected={peer.user_hash == @peer_hash_input}>
              {peer.name} ({short_hash(peer.user_hash)})
            </option>
          <% end %>
        </select>
        <button
          type="submit"
          disabled={@operation_in_progress || @peer_hash_input == ""}
          class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 disabled:bg-gray-400 text-sm font-medium"
        >
          New Dialog
        </button>
      </form>

      <%= if @dialogs == [] do %>
        <p class="text-sm text-gray-500 italic">No dialogs yet. Create one or click Refresh.</p>
      <% else %>
        <div class="space-y-2">
          <%= for dialog <- @dialogs do %>
            <button
              phx-click="select_dialog"
              phx-value-dialog_hash={dialog.dialog_hash}
              phx-value-peer_hash={dialog.peer_hash}
              class={"w-full text-left p-3 rounded border #{if @selected_dialog == dialog.dialog_hash, do: "border-blue-500 bg-blue-50", else: "border-gray-200 hover:bg-gray-50"}"}
            >
              <div class="text-sm font-mono truncate">{short_hash(dialog.peer_hash)}</div>
              <div class="text-xs text-gray-500 mt-1 font-mono truncate">
                {short_hash(dialog.dialog_hash)}
              </div>
            </button>
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end

  def render_messages_section(assigns) do
    ~H"""
    <section class="bg-white shadow rounded-lg p-6">
      <div class="flex justify-between items-center mb-4">
        <h3 class="text-lg font-bold">3. Messages</h3>
        <button
          phx-click="refresh_messages"
          class="px-3 py-1 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 text-sm"
        >
          Refresh
        </button>
      </div>

      <div class="border rounded-lg p-4 mb-4 max-h-96 overflow-y-auto bg-gray-50 space-y-3">
        <%= if @messages == [] do %>
          <p class="text-sm text-gray-500 italic text-center">No messages yet</p>
        <% else %>
          <%= for msg <- @messages do %>
            <div class={"p-3 rounded-lg max-w-[80%] #{if msg.sender_hash == @user.user_hash, do: "ml-auto bg-blue-100", else: "bg-white border"}"}>
              <div class="text-xs text-gray-500 mb-1">
                {if msg.sender_hash == @user.user_hash,
                  do: "You",
                  else: short_hash(msg.sender_hash)}
              </div>
              <div class="text-sm">{msg.content}</div>
              <div class="text-xs text-gray-400 mt-1">{msg.owner_timestamp}</div>
            </div>
          <% end %>
        <% end %>
      </div>

      <form phx-submit="send_message" class="flex gap-2">
        <input
          type="text"
          name="text"
          value={@compose_text}
          placeholder="Type a message..."
          class="flex-1 px-3 py-2 border rounded text-sm"
          autocomplete="off"
        />
        <button
          type="submit"
          disabled={@operation_in_progress}
          class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400 text-sm font-medium"
        >
          Send
        </button>
      </form>
    </section>
    """
  end

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
    <aside class="w-96 bg-gray-50 border-l overflow-y-auto p-4">
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
            <div class="bg-white p-3 rounded shadow-sm text-xs">
              <div class="flex justify-between items-center mb-1">
                <span class="font-mono font-bold">
                  {log.method} {URI.parse(log.url).path}
                </span>
                <span class={"px-2 py-0.5 rounded #{status_color(log.response_status)}"}>
                  {log.response_status}
                </span>
              </div>
              <details>
                <summary class="text-gray-500 cursor-pointer">Details</summary>
                <pre class="mt-1 bg-gray-100 p-2 rounded overflow-x-auto max-h-40 overflow-y-auto whitespace-pre-wrap break-all">{log.response_body}</pre>
              </details>
            </div>
          <% end %>
        </div>
      <% end %>
    </aside>
    """
  end

  defp short_hash(nil), do: "?"
  defp short_hash(hash), do: String.slice(hash, 0, 18) <> "..."

  defp status_color(s) when s >= 200 and s < 300, do: "bg-green-100 text-green-800"
  defp status_color(s) when s >= 400, do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end
