defmodule ChatWeb.ElectricLive.DialogSandboxLive.Index do
  use ChatWeb, :live_view

  import ChatWeb.ElectricLive.DialogSandboxLive.Components

  alias ChatWeb.ElectricLive.DialogSandboxLive.{Dialogs, Messages, Reactions, Receipts, Versions}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:user, nil)
      |> assign(:dialogs, [])
      |> assign(:selected_dialog, nil)
      |> assign(:messages, [])
      |> assign(:msg_keys_cache, %{})
      |> assign(:compose_text, "")
      |> assign(:refs_tails, %{})
      |> assign(:peer_hash_input, "")
      |> assign(:available_peers, [])
      |> assign(:request_log, [])
      |> assign(:reactions, %{})
      |> assign(:receipts, %{})
      |> assign(:editing_message_id, nil)
      |> assign(:expanded_versions, MapSet.new())
      |> assign(:message_versions, %{})
      |> assign(:show_docs, true)
      |> assign(:show_log, true)
      |> assign(:expanded_docs, MapSet.new(["dialog_keys"]))
      |> assign(:operation_in_progress, false)
      |> assign(:error_message, nil)
      |> assign(:stream_pid, nil)
      |> assign(:reaction_stream_pid, nil)
      |> assign(:receipt_stream_pid, nil)
      |> assign(:sync_status, :idle)
      |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="x-sandbox h-screen flex flex-col bg-gray-50" id="dialog-sandbox">
      <div class="bg-white border-b px-6 py-4">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold text-gray-900">Dialog Sandbox</h1>
            <p class="text-sm text-gray-600 mt-1">Two-party encrypted dialog via Electric API</p>
          </div>
          <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800">← Electric Index</a>
        </div>
      </div>

      <div class="flex-1 flex overflow-hidden">
        <.render_docs_sidebar show_docs={@show_docs} expanded_docs={@expanded_docs} />
        <main class="flex-1 overflow-y-auto p-6">
          <.render_error error_message={@error_message} />
          <.render_identity_section user={@user} uploads={@uploads} />
          <%= if @user do %>
            <.render_dialogs_section
              dialogs={@dialogs}
              selected_dialog={@selected_dialog}
              peer_hash_input={@peer_hash_input}
              available_peers={@available_peers}
              operation_in_progress={@operation_in_progress}
            />
          <% end %>
          <%= if @user && @selected_dialog do %>
            <.render_messages_section
              messages={@messages}
              user={@user}
              compose_text={@compose_text}
              operation_in_progress={@operation_in_progress}
              sync_status={@sync_status}
              reactions={@reactions}
              receipts={@receipts}
              editing_message_id={@editing_message_id}
              expanded_versions={@expanded_versions}
              message_versions={@message_versions}
            />
          <% end %>
        </main>
        <.render_request_log request_log={@request_log} show_log={@show_log} />
      </div>
    </div>
    """
  end

  # --- Event Handlers ---

  @impl true
  def handle_event("validate_key_file", _params, socket), do: {:noreply, socket}

  def handle_event("import_keys", _params, socket),
    do: {:noreply, Dialogs.import_keys(socket)}

  def handle_event("fetch_dialogs", _params, socket),
    do: {:noreply, Dialogs.fetch_dialogs(socket)}

  def handle_event("select_peer", %{"peer_hash" => hash}, socket) do
    {:noreply, assign(socket, :peer_hash_input, hash)}
  end

  def handle_event("create_dialog", %{"peer_hash" => peer_hash}, socket),
    do: {:noreply, Dialogs.create_dialog(socket, peer_hash)}

  def handle_event("select_dialog", %{"dialog_hash" => hash, "peer_hash" => peer_hash}, socket),
    do: {:noreply, Dialogs.select_dialog(socket, hash, peer_hash)}

  def handle_event("refresh_messages", _params, socket),
    do: {:noreply, Dialogs.refresh_messages(socket)}

  def handle_event("send_message", %{"text" => text}, socket) when text != "",
    do: {:noreply, Messages.send_message(socket, text)}

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("start_edit", %{"message_id" => msg_id}, socket) do
    {:noreply, assign(socket, :editing_message_id, msg_id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_message_id, nil)}
  end

  def handle_event("toggle_versions", %{"message_id" => msg_id}, socket),
    do: {:noreply, Versions.toggle(socket, msg_id)}

  def handle_event("save_edit", %{"text" => text, "message_id" => msg_id}, socket)
      when text != "",
      do: {:noreply, Messages.save_edit(socket, msg_id, text)}

  def handle_event("save_edit", _params, socket), do: {:noreply, socket}

  def handle_event("delete_message", %{"message_id" => msg_id}, socket),
    do: {:noreply, Messages.delete_message(socket, msg_id)}

  def handle_event(
        "react",
        %{"message_id" => msg_id, "sign_hash" => sign_hash, "emoji" => emoji},
        socket
      ),
      do: {:noreply, Reactions.react(socket, {msg_id, sign_hash, emoji})}

  def handle_event(
        "send_receipt",
        %{"message_id" => msg_id, "sign_hash" => sign_hash, "type" => type},
        socket
      ),
      do: {:noreply, Receipts.send_receipt(socket, msg_id, sign_hash, type)}

  def handle_event("toggle_docs", _params, socket) do
    {:noreply, assign(socket, :show_docs, !socket.assigns.show_docs)}
  end

  def handle_event("toggle_log", _params, socket) do
    {:noreply, assign(socket, :show_log, !socket.assigns.show_log)}
  end

  def handle_event("toggle_doc_section", %{"section" => section}, socket) do
    expanded =
      if section in socket.assigns.expanded_docs,
        do: MapSet.delete(socket.assigns.expanded_docs, section),
        else: MapSet.put(socket.assigns.expanded_docs, section)

    {:noreply, assign(socket, :expanded_docs, expanded)}
  end

  def handle_event("clear_log", _params, socket),
    do: {:noreply, assign(socket, :request_log, [])}

  def handle_event("clear_error", _params, socket),
    do: {:noreply, assign(socket, :error_message, nil)}

  # --- Stream handlers ---

  @impl true
  def handle_info({:dialog_msgs_loaded, raw_msgs}, socket),
    do: {:noreply, Messages.loaded(socket, raw_msgs)}

  def handle_info({:dialog_msg_new, raw_msg}, socket),
    do: {:noreply, Messages.new_message(socket, raw_msg)}

  def handle_info({:dialog_msg_updated, raw_msg}, socket),
    do: {:noreply, Messages.updated_message(socket, raw_msg)}

  def handle_info({:dialog_msg_live}, socket) do
    {:noreply, assign(socket, :sync_status, :live)}
  end

  def handle_info({:reactions_loaded, raw_reactions}, socket),
    do: {:noreply, Reactions.loaded(socket, raw_reactions)}

  def handle_info({:reaction_change, raw}, socket),
    do: {:noreply, Reactions.changed(socket, raw)}

  def handle_info({:receipts_loaded, raw_receipts}, socket),
    do: {:noreply, Receipts.loaded(socket, raw_receipts)}

  def handle_info({:receipt_change, raw}, socket),
    do: {:noreply, Receipts.changed(socket, raw)}
end
