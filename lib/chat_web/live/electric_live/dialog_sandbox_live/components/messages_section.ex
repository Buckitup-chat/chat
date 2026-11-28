defmodule ChatWeb.ElectricLive.DialogSandboxLive.Components.MessagesSection do
  @moduledoc false

  use Phoenix.Component

  import ChatWeb.ElectricLive.DialogSandboxLive.Components.MessageParts

  alias Chat.Proto.Shortcode
  alias ChatWeb.ElectricLive.DialogSandboxLive.ContentComponents

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
                <span>{if is_own, do: "You", else: Shortcode.short_code(msg.sender_hash)}</span>
                <span class="relative group font-mono text-gray-400 cursor-default">
                  {Shortcode.short_code(msg.message_id)}
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
end
