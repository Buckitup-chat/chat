defmodule ChatWeb.ElectricLive.DialogSandboxLive.Components do
  @moduledoc false

  use Phoenix.Component

  alias ChatWeb.ElectricLive.DialogSandboxLive.ContentComponents
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

  @emojis ~w(👍 ❤️ 😂 😮 😢 🎉)

  def render_messages_section(assigns) do
    ~H"""
    <section class="bg-white shadow rounded-lg p-6">
      <div class="flex justify-between items-center mb-4">
        <h3 class="text-lg font-bold">3. Messages</h3>
        <div class="flex items-center gap-3">
          <.sync_badge status={@sync_status} />
          <button
            phx-click="refresh_messages"
            class="px-3 py-1 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 text-sm"
          >
            Reconnect
          </button>
        </div>
      </div>

      <div class="border rounded-lg p-4 mb-4 max-h-96 overflow-y-auto bg-gray-50 space-y-3">
        <%= if @messages == [] do %>
          <p class="text-sm text-gray-500 italic text-center">No messages yet</p>
        <% else %>
          <%= for msg <- @messages do %>
            <% msg_reactions = Map.get(@reactions, msg.sign_hash, []) %>
            <% msg_receipts = Map.get(@receipts, msg.message_id, []) %>
            <% is_own = msg.sender_hash == @user.user_hash %>
            <% has_history = msg.parent_sign_hash != nil %>
            <% versions_expanded = msg.message_id in @expanded_versions %>
            <% versions = Map.get(@message_versions, msg.message_id, []) %>
            <div class={"p-3 rounded-lg max-w-[80%] #{if is_own, do: "ml-auto bg-blue-100", else: "bg-white border"}"}>
              <div class="flex justify-between text-xs text-gray-500 mb-1">
                <span>{if is_own, do: "You", else: short_hash(msg.sender_hash)}</span>
                <span class="relative group font-mono text-gray-400 cursor-default">
                  {short_hash(msg.message_id)}
                  <span class="absolute bottom-full right-0 mb-1 px-2 py-1 bg-gray-900 text-white text-[10px] font-mono rounded whitespace-nowrap invisible group-hover:visible z-10">
                    {msg.sign_hash}
                  </span>
                </span>
              </div>
              <%= if @editing_message_id == msg.message_id do %>
                <.edit_form
                  message_id={msg.message_id}
                  current_content={unwrap_for_edit(msg.content_json)}
                />
              <% else %>
                <ContentComponents.render_content
                  content={msg.content}
                  message_id={msg.message_id}
                  deleted={msg.deleted}
                />
              <% end %>
              <%= unless msg.deleted do %>
                <.refs_list refs_map={msg.refs_map} />
                <.reaction_display reactions={msg_reactions} />
                <%= unless is_own do %>
                  <.emoji_buttons message_id={msg.message_id} sign_hash={msg.sign_hash} />
                <% end %>
              <% end %>
              <div class="flex justify-between items-center mt-1">
                <span class="text-xs text-gray-400">
                  {format_timestamp(msg.owner_timestamp)}
                  <%= if has_history do %>
                    <button
                      phx-click="toggle_versions"
                      phx-value-message_id={msg.message_id}
                      class="italic ml-1 text-blue-500 hover:text-blue-700 cursor-pointer"
                    >
                      ({if msg.deleted, do: "deleted", else: "edited"} {if versions_expanded,
                        do: "▲",
                        else: "▼"})
                    </button>
                  <% end %>
                </span>
                <div class="flex items-center gap-2">
                  <%= if is_own && !msg.deleted && @editing_message_id != msg.message_id do %>
                    <.message_actions message_id={msg.message_id} />
                  <% end %>
                  <%= if is_own do %>
                    <.receipt_status receipts={msg_receipts} />
                  <% else %>
                    <%= unless msg.deleted do %>
                      <.receipt_buttons
                        message_id={msg.message_id}
                        sign_hash={msg.sign_hash}
                        receipts={msg_receipts}
                        user_hash={@user.user_hash}
                      />
                    <% end %>
                  <% end %>
                </div>
              </div>
              <%= if has_history && versions_expanded do %>
                <.version_history versions={versions} reactions={@reactions} />
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>

      <form phx-submit="send_message" class="flex gap-2">
        <textarea
          name="text"
          rows="2"
          placeholder="Type a message or paste content JSON..."
          class="flex-1 px-3 py-2 border rounded text-sm resize-y"
          autocomplete="off"
        >{@compose_text}</textarea>
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

  defp reaction_display(%{reactions: []} = assigns), do: ~H""

  defp reaction_display(assigns) do
    assigns = assign(assigns, :grouped, Enum.frequencies_by(assigns.reactions, & &1.emoji))

    ~H"""
    <div class="flex flex-wrap gap-1 mt-1">
      <%= for {emoji, count} <- @grouped do %>
        <span class="inline-flex items-center gap-0.5 px-1.5 py-0.5 bg-gray-100 rounded-full text-xs">
          <span>{emoji}</span>
          <%= if count > 1 do %>
            <span class="text-gray-500">{count}</span>
          <% end %>
        </span>
      <% end %>
    </div>
    """
  end

  defp version_history(%{versions: []} = assigns) do
    ~H"""
    <div class="mt-2 pl-3 border-l-2 border-gray-300 text-xs text-gray-400 italic">
      Loading...
    </div>
    """
  end

  defp version_history(assigns) do
    ~H"""
    <div class="mt-2 pl-3 border-l-2 border-gray-300 space-y-1">
      <%= for v <- @versions do %>
        <div class="text-xs text-gray-500">
          <span class="text-gray-400">{format_timestamp(v.owner_timestamp)}</span>
          <span class="ml-1">
            <ContentComponents.render_content
              content={v.content}
              message_id={"#{v.message_id}-v#{v.sign_hash}"}
              deleted={v.deleted}
            />
          </span>
          <.reaction_display reactions={Map.get(@reactions, v.sign_hash, [])} />
        </div>
      <% end %>
    </div>
    """
  end

  defp emoji_buttons(assigns) do
    assigns = assign(assigns, :emojis, @emojis)

    ~H"""
    <div class="flex gap-0.5 mt-1">
      <%= for emoji <- @emojis do %>
        <button
          phx-click="react"
          phx-value-message_id={@message_id}
          phx-value-sign_hash={@sign_hash}
          phx-value-emoji={emoji}
          class="px-1 py-0.5 hover:bg-gray-200 rounded text-sm cursor-pointer"
          title={"React with #{emoji}"}
        >
          {emoji}
        </button>
      <% end %>
    </div>
    """
  end

  defp edit_form(assigns) do
    ~H"""
    <form phx-submit="save_edit" class="flex gap-2">
      <input type="hidden" name="message_id" value={@message_id} />
      <input
        type="text"
        name="text"
        value={@current_content}
        class="flex-1 px-2 py-1 border rounded text-sm"
        autocomplete="off"
        autofocus
      />
      <button type="submit" class="px-2 py-1 bg-green-600 text-white rounded text-xs font-medium">
        Save
      </button>
      <button
        type="button"
        phx-click="cancel_edit"
        class="px-2 py-1 bg-gray-300 text-gray-700 rounded text-xs"
      >
        Cancel
      </button>
    </form>
    """
  end

  defp message_actions(assigns) do
    ~H"""
    <div class="flex gap-1">
      <button
        phx-click="start_edit"
        phx-value-message_id={@message_id}
        class="text-[10px] px-1.5 py-0.5 bg-gray-100 hover:bg-gray-200 rounded text-gray-600"
      >
        Edit
      </button>
      <button
        phx-click="delete_message"
        phx-value-message_id={@message_id}
        class="text-[10px] px-1.5 py-0.5 bg-red-50 hover:bg-red-100 rounded text-red-600"
        data-confirm="Delete this message?"
      >
        Delete
      </button>
    </div>
    """
  end

  defp receipt_status(%{receipts: []} = assigns) do
    ~H"""
    <span class="text-xs text-gray-400">✓ sent</span>
    """
  end

  defp receipt_status(assigns) do
    assigns = assign(assigns, :has_read, Enum.any?(assigns.receipts, &(&1.type == "read")))

    ~H"""
    <span class={
      "text-xs #{if @has_read, do: "text-blue-500 font-medium", else: "text-green-600"}"
    }>
      {if @has_read, do: "✓✓ read", else: "✓✓ delivered"}
    </span>
    """
  end

  defp receipt_buttons(assigns) do
    assigns =
      assign(
        assigns,
        :already_sent,
        assigns.receipts
        |> Enum.filter(&(&1.peer_hash == assigns.user_hash))
        |> Enum.map(& &1.type)
        |> MapSet.new()
      )

    ~H"""
    <div class="flex gap-1">
      <%= unless "delivered" in @already_sent do %>
        <button
          phx-click="send_receipt"
          phx-value-message_id={@message_id}
          phx-value-sign_hash={@sign_hash}
          phx-value-type="delivered"
          class="text-[10px] px-1.5 py-0.5 bg-gray-100 hover:bg-gray-200 rounded text-gray-600"
        >
          ✓ Delivered
        </button>
      <% end %>
      <%= unless "read" in @already_sent do %>
        <button
          phx-click="send_receipt"
          phx-value-message_id={@message_id}
          phx-value-sign_hash={@sign_hash}
          phx-value-type="read"
          class="text-[10px] px-1.5 py-0.5 bg-blue-50 hover:bg-blue-100 rounded text-blue-600"
        >
          ✓✓ Read
        </button>
      <% end %>
    </div>
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
    </aside>
    """
  end

  defp refs_list(%{refs_map: refs} = assigns) when map_size(refs) == 0 do
    ~H""
  end

  defp refs_list(assigns) do
    ~H"""
    <div class="mt-1 flex flex-wrap gap-1">
      <span class="text-[10px] text-gray-400">refs:</span>
      <%= for {msg_id, sign_hash} <- @refs_map do %>
        <span class="relative group">
          <span class="text-[10px] font-mono text-indigo-500 cursor-default">
            {short_hash(msg_id)}
          </span>
          <span class="absolute bottom-full left-0 mb-1 px-2 py-1 bg-gray-900 text-white text-[10px] font-mono rounded whitespace-nowrap invisible group-hover:visible z-10">
            {sign_hash}
          </span>
        </span>
      <% end %>
    </div>
    """
  end

  defp sync_badge(%{status: :loading} = assigns) do
    ~H"""
    <span class="text-xs text-yellow-600 animate-pulse">Syncing...</span>
    """
  end

  defp sync_badge(%{status: :loaded} = assigns) do
    ~H"""
    <span class="text-xs text-green-600">Synced</span>
    """
  end

  defp sync_badge(%{status: :live} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 text-xs text-green-700">
      <span class="w-2 h-2 rounded-full bg-green-500 animate-pulse"></span> Live
    </span>
    """
  end

  defp sync_badge(assigns) do
    ~H"""
    <span class="text-xs text-gray-500">Idle</span>
    """
  end

  defp format_timestamp(ts) when is_number(ts) do
    ts
    |> DateTime.from_unix!()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_timestamp(ts) when is_binary(ts) do
    case Integer.parse(ts) do
      {n, ""} -> format_timestamp(n)
      _ -> ts
    end
  end

  defp format_timestamp(ts), do: inspect(ts)

  defp short_hash(nil), do: "?"
  defp short_hash(hash), do: String.slice(hash, 0, 18) <> "..."

  defp format_resp_headers(headers) when is_map(headers) do
    Enum.flat_map(headers, fn {k, vs} ->
      Enum.map(List.wrap(vs), &{k, &1})
    end)
  end

  defp format_resp_headers(headers) when is_list(headers), do: headers
  defp format_resp_headers(_), do: []

  defp unwrap_for_edit(nil), do: ""

  defp unwrap_for_edit(json) do
    case Jason.decode(json) do
      {:ok, string} when is_binary(string) -> string
      _ -> json
    end
  end

  defp status_color(s) when s >= 200 and s < 300, do: "bg-green-100 text-green-800"
  defp status_color(s) when s >= 400, do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end
