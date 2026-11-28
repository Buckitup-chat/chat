defmodule ChatWeb.ElectricLive.DialogSandboxLive.Components do
  @moduledoc false

  use Phoenix.Component

  alias Chat.Proto.Shortcode
  alias ChatWeb.ElectricLive.Components
  alias ChatWeb.ElectricLive.DialogSandboxLive.Components.MessagesSection
  alias ChatWeb.ElectricLive.DialogSandboxLive.Components.Sidebars

  defdelegate render_messages_section(assigns), to: MessagesSection
  defdelegate render_docs_sidebar(assigns), to: Sidebars
  defdelegate render_request_log(assigns), to: Sidebars

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
          <span class="font-mono text-gray-600">{Shortcode.short_code(@user.user_hash)}</span>
          <span class="text-gray-500">({@user.name})</span>
        </div>
        <Components.identity_not_on_server identity={@user} />
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
              {peer.name} ({Shortcode.short_code(peer.user_hash)})
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
              <div class="text-sm font-mono truncate">{Shortcode.short_code(dialog.peer_hash)}</div>
              <div class="text-xs text-gray-500 mt-1 font-mono truncate">
                {Shortcode.short_code(dialog.dialog_hash)}
              </div>
            </button>
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end
end
