defmodule ChatWeb.ElectricLive.DialogSandboxLive.Index do
  use ChatWeb, :live_view

  import ChatWeb.ElectricLive.DialogSandboxLive.Components

  alias ChatWeb.ElectricLive.DialogSandboxLive.{ApiClient, Crypto}

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
      |> assign(:show_docs, true)
      |> assign(:expanded_docs, MapSet.new(["dialog_keys"]))
      |> assign(:operation_in_progress, false)
      |> assign(:error_message, nil)
      |> assign(:stream_pid, nil)
      |> assign(:sync_status, :idle)
      |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-gray-50" id="dialog-sandbox">
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
            />
          <% end %>
        </main>
        <.render_request_log request_log={@request_log} />
      </div>
    </div>
    """
  end

  # --- Event Handlers ---

  @impl true
  def handle_event("validate_key_file", _params, socket), do: {:noreply, socket}

  def handle_event("import_keys", _params, socket) do
    [result] =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    socket =
      case Crypto.parse_and_validate_identity(result) do
        {:ok, user_data} ->
          socket
          |> assign(:user, user_data)
          |> assign(:dialogs, [])
          |> assign(:selected_dialog, nil)
          |> assign(:messages, [])
          |> assign(:msg_keys_cache, %{})
          |> assign(:error_message, nil)
          |> fetch_available_peers(user_data.user_hash)

        {:error, reason} ->
          assign(socket, :error_message, "Import failed: #{reason}")
      end

    {:noreply, socket}
  end

  def handle_event("fetch_dialogs", _params, socket) do
    base_url = get_base_url(socket)
    user_hash = socket.assigns.user.user_hash

    socket =
      case ApiClient.fetch_dialog_keys(user_hash, base_url) do
        {:ok, %{keys: keys, log_entries: logs}} ->
          dialogs = Crypto.build_dialog_list(keys, user_hash)

          socket
          |> assign(:dialogs, dialogs)
          |> update(:request_log, &(&1 ++ logs))

        {:error, %{reason: reason, log_entries: logs}} ->
          socket
          |> assign(:error_message, reason)
          |> update(:request_log, &(&1 ++ logs))
      end

    {:noreply, fetch_available_peers(socket, user_hash)}
  end

  def handle_event("select_peer", %{"peer_hash" => hash}, socket) do
    {:noreply, assign(socket, :peer_hash_input, hash)}
  end

  def handle_event("create_dialog", %{"peer_hash" => peer_hash}, socket) do
    %{user: user} = socket.assigns
    base_url = get_base_url(socket)

    socket = assign(socket, :operation_in_progress, true)

    with {:ok, %{card: card, log_entries: card_logs}} <-
           ApiClient.fetch_user_card(peer_hash, base_url),
         peer_crypt_pkey <- Crypto.decode_binary_field(card["crypt_pkey"]),
         {:ok, %{dialog_hash: dialog_hash, log_entries: key_logs}} <-
           ApiClient.publish_dialog_key(user, peer_hash, peer_crypt_pkey, base_url) do
      dialog = %{dialog_hash: dialog_hash, peer_hash: peer_hash}

      {:noreply,
       socket
       |> update(:dialogs, &[dialog | &1])
       |> assign(:selected_dialog, dialog_hash)
       |> assign(:peer_hash_input, "")
       |> assign(:operation_in_progress, false)
       |> update(:request_log, &(&1 ++ card_logs ++ key_logs))}
    else
      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(:error_message, reason)
         |> assign(:operation_in_progress, false)
         |> update(:request_log, &(&1 ++ logs))}
    end
  end

  def handle_event("select_dialog", %{"dialog_hash" => hash, "peer_hash" => peer_hash}, socket) do
    %{user: user} = socket.assigns
    base_url = get_base_url(socket)

    my_key =
      Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)

    keys_cache =
      %{user.user_hash => my_key}
      |> maybe_unwrap_peer_key(peer_hash, user, base_url)

    {:noreply,
     socket
     |> assign(:selected_dialog, hash)
     |> assign(:messages, [])
     |> assign(:refs_tails, %{})
     |> assign(:reactions, %{})
     |> assign(:receipts, %{})
     |> assign(:msg_keys_cache, keys_cache)
     |> start_dialog_stream(hash)}
  end

  def handle_event("refresh_messages", _params, socket) do
    dialog =
      Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == socket.assigns.selected_dialog))

    case dialog do
      nil -> {:noreply, socket}
      d -> {:noreply, start_dialog_stream(socket, d.dialog_hash)}
    end
  end

  def handle_event("send_message", %{"text" => text}, socket) when text != "" do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    dialog = Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == dialog_hash))
    base_url = get_base_url(socket)
    refs_tails = %{peer_hash: dialog.peer_hash, tails: socket.assigns.refs_tails}

    socket = assign(socket, :operation_in_progress, true)

    with {:ok, socket} <- ensure_dialog_key(socket, user, dialog.peer_hash, base_url),
         {:ok, %{message_id: msg_id, sign_hash: sign_hash, log_entries: logs}} <-
           ApiClient.publish_dialog_message(user, dialog_hash, text, refs_tails, base_url) do
      {:noreply,
       socket
       |> assign(:compose_text, "")
       |> assign(:refs_tails, %{msg_id => sign_hash})
       |> assign(:operation_in_progress, false)
       |> update(:request_log, &(&1 ++ logs))}
    else
      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(:error_message, reason)
         |> assign(:operation_in_progress, false)
         |> update(:request_log, &(&1 ++ logs))}
    end
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("start_edit", %{"message_id" => msg_id}, socket) do
    {:noreply, assign(socket, :editing_message_id, msg_id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_message_id, nil)}
  end

  def handle_event("save_edit", %{"text" => text, "message_id" => msg_id}, socket)
      when text != "" do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    dialog = Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == dialog_hash))
    base_url = get_base_url(socket)
    refs_tails = %{peer_hash: dialog.peer_hash, tails: socket.assigns.refs_tails}

    socket = assign(socket, :operation_in_progress, true)

    with {:ok, %{sign_hash: current_sign_hash}} <-
           find_own_message(socket.assigns.messages, msg_id, user.user_hash),
         {:ok, %{sign_hash: new_sign_hash, log_entries: logs}} <-
           ApiClient.publish_edit_message(
             user,
             dialog_hash,
             msg_id,
             current_sign_hash,
             text,
             refs_tails,
             base_url
           ) do
      {:noreply,
       socket
       |> assign(:editing_message_id, nil)
       |> assign(:operation_in_progress, false)
       |> assign(:refs_tails, %{msg_id => new_sign_hash})
       |> update(:request_log, &(&1 ++ logs))}
    else
      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(:error_message, reason)
         |> assign(:operation_in_progress, false)
         |> update(:request_log, &(&1 ++ logs))}
    end
  end

  def handle_event("save_edit", _params, socket), do: {:noreply, socket}

  def handle_event("delete_message", %{"message_id" => msg_id}, socket) do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    dialog = Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == dialog_hash))
    base_url = get_base_url(socket)
    refs_tails = %{peer_hash: dialog.peer_hash, tails: socket.assigns.refs_tails}

    socket = assign(socket, :operation_in_progress, true)

    with {:ok, %{sign_hash: current_sign_hash}} <-
           find_own_message(socket.assigns.messages, msg_id, user.user_hash),
         {:ok, %{log_entries: logs}} <-
           ApiClient.publish_delete_message(
             user,
             dialog_hash,
             msg_id,
             current_sign_hash,
             refs_tails,
             base_url
           ) do
      {:noreply,
       socket
       |> assign(:operation_in_progress, false)
       |> update(:request_log, &(&1 ++ logs))}
    else
      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(:error_message, reason)
         |> assign(:operation_in_progress, false)
         |> update(:request_log, &(&1 ++ logs))}
    end
  end

  def handle_event(
        "react",
        %{"message_id" => msg_id, "sign_hash" => sign_hash, "emoji" => emoji},
        socket
      ) do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    dialog = Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == dialog_hash))
    base_url = get_base_url(socket)

    case ApiClient.publish_reaction(
           user,
           dialog_hash,
           msg_id,
           sign_hash,
           emoji,
           dialog.peer_hash,
           base_url
         ) do
      {:ok, %{log_entries: logs}} ->
        {:noreply,
         socket
         |> update(:request_log, &(&1 ++ logs))
         |> fetch_reactions_and_receipts()}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(:error_message, reason)
         |> update(:request_log, &(&1 ++ logs))}
    end
  end

  def handle_event(
        "send_receipt",
        %{"message_id" => msg_id, "sign_hash" => sign_hash, "type" => type},
        socket
      ) do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    base_url = get_base_url(socket)

    case ApiClient.publish_receipt(user, dialog_hash, msg_id, sign_hash, type, base_url) do
      {:ok, %{log_entries: logs}} ->
        {:noreply,
         socket
         |> update(:request_log, &(&1 ++ logs))
         |> fetch_reactions_and_receipts()}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(:error_message, reason)
         |> update(:request_log, &(&1 ++ logs))}
    end
  end

  def handle_event("toggle_docs", _params, socket) do
    {:noreply, assign(socket, :show_docs, !socket.assigns.show_docs)}
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
  def handle_info({:dialog_msgs_loaded, raw_msgs}, socket) do
    keys_cache = socket.assigns.msg_keys_cache
    sorted = Enum.sort_by(raw_msgs, & &1["owner_timestamp"])
    messages = Enum.map(sorted, &Crypto.decrypt_single_message(&1, keys_cache))
    tails = Crypto.compute_tails(sorted, keys_cache)

    {:noreply,
     socket
     |> assign(messages: messages, refs_tails: tails, sync_status: :loaded)
     |> fetch_reactions_and_receipts()}
  end

  def handle_info({:dialog_msg_new, raw_msg}, socket) do
    already_exists =
      Enum.any?(socket.assigns.messages, &(&1.message_id == raw_msg["message_id"]))

    if already_exists do
      {:noreply, socket}
    else
      msg = Crypto.decrypt_single_message(raw_msg, socket.assigns.msg_keys_cache)

      {:noreply,
       socket
       |> update(:messages, &(&1 ++ [msg]))
       |> assign(:refs_tails, %{raw_msg["message_id"] => raw_msg["sign_hash"]})}
    end
  end

  def handle_info({:dialog_msg_updated, raw_msg}, socket) do
    msg_id = raw_msg["message_id"]
    decrypted = Crypto.decrypt_single_message(raw_msg, socket.assigns.msg_keys_cache)

    {:noreply,
     socket
     |> update(:messages, &upsert_message(&1, msg_id, decrypted))
     |> update(:refs_tails, &Map.put(&1, msg_id, raw_msg["sign_hash"]))}
  end

  def handle_info({:dialog_msg_live}, socket) do
    {:noreply, assign(socket, :sync_status, :live)}
  end

  # --- Private ---

  defp start_dialog_stream(socket, dialog_hash) do
    socket = stop_dialog_stream(socket)
    base_url = get_base_url(socket)
    stream_pid = ApiClient.start_message_stream(dialog_hash, base_url, self())
    assign(socket, stream_pid: stream_pid, sync_status: :loading)
  end

  defp stop_dialog_stream(socket) do
    case socket.assigns[:stream_pid] do
      pid when is_pid(pid) ->
        Process.exit(pid, :kill)
        assign(socket, :stream_pid, nil)

      _ ->
        socket
    end
  end

  defp fetch_available_peers(socket, my_hash) do
    base_url = get_base_url(socket)

    case ApiClient.fetch_all_user_cards(base_url) do
      {:ok, %{cards: cards, log_entries: logs}} ->
        peers =
          cards
          |> Enum.reject(&(&1["user_hash"] == my_hash))
          |> Enum.map(&%{user_hash: &1["user_hash"], name: &1["name"]})

        socket
        |> assign(:available_peers, peers)
        |> update(:request_log, &(&1 ++ logs))

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(:error_message, reason)
        |> update(:request_log, &(&1 ++ logs))
    end
  end

  defp ensure_dialog_key(socket, user, peer_hash, base_url) do
    dialog_hash = Crypto.compute_dialog_hash(user.user_hash, peer_hash)

    case ApiClient.fetch_dialog_keys_by_dialog(dialog_hash, base_url) do
      {:ok, %{keys: keys, log_entries: logs}} ->
        socket = update(socket, :request_log, &(&1 ++ logs))
        has_own_key = Enum.any?(keys, &(&1["sender_hash"] == user.user_hash))

        if has_own_key do
          {:ok, socket}
        else
          with {:ok, %{card: card, log_entries: card_logs}} <-
                 ApiClient.fetch_user_card(peer_hash, base_url),
               peer_crypt_pkey = Crypto.decode_binary_field(card["crypt_pkey"]),
               {:ok, %{log_entries: key_logs}} <-
                 ApiClient.publish_dialog_key(user, peer_hash, peer_crypt_pkey, base_url) do
            {:ok, update(socket, :request_log, &(&1 ++ card_logs ++ key_logs))}
          end
        end

      {:error, _} = error ->
        error
    end
  end

  defp maybe_unwrap_peer_key(keys_cache, peer_hash, user, base_url) do
    if Map.has_key?(keys_cache, peer_hash) do
      keys_cache
    else
      dialog_hash = Crypto.compute_dialog_hash(user.user_hash, peer_hash)

      with {:ok, %{keys: keys}} <- ApiClient.fetch_dialog_keys_by_dialog(dialog_hash, base_url),
           %{} = row <-
             Enum.find(keys, &(&1["sender_hash"] == peer_hash)) do
        kem_wrap = Crypto.decode_binary_field(row["peer_kem_wrap_key_b64"])
        wrapped = Crypto.decode_binary_field(row["peer_wrapped_msg_key_b64"])
        Map.put(keys_cache, peer_hash, Crypto.unwrap_peer_key(kem_wrap, wrapped, user.crypt_skey))
      else
        _ -> keys_cache
      end
    end
  end

  defp fetch_reactions_and_receipts(socket) do
    %{selected_dialog: dialog_hash, msg_keys_cache: keys_cache} = socket.assigns
    base_url = get_base_url(socket)

    {reactions, logs1} = fetch_and_decrypt_reactions(dialog_hash, keys_cache, base_url)
    {receipts, logs2} = fetch_and_parse_receipts(dialog_hash, base_url)

    socket
    |> assign(reactions: reactions, receipts: receipts)
    |> update(:request_log, &(&1 ++ logs1 ++ logs2))
  end

  defp fetch_and_decrypt_reactions(dialog_hash, keys_cache, base_url) do
    case ApiClient.fetch_reactions(dialog_hash, base_url) do
      {:ok, %{reactions: raw, log_entries: logs}} ->
        {Crypto.group_reactions_by_message(raw, keys_cache), logs}

      {:error, %{log_entries: logs}} ->
        {%{}, logs}
    end
  end

  defp fetch_and_parse_receipts(dialog_hash, base_url) do
    case ApiClient.fetch_receipts(dialog_hash, base_url) do
      {:ok, %{receipts: raw, log_entries: logs}} ->
        {Crypto.group_receipts_by_message(raw), logs}

      {:error, %{log_entries: logs}} ->
        {%{}, logs}
    end
  end

  defp find_own_message(messages, msg_id, user_hash) do
    case Enum.find(messages, &(&1.message_id == msg_id)) do
      %{sender_hash: ^user_hash} = msg -> {:ok, msg}
      %{} -> {:error, %{reason: "Can only modify own messages", log_entries: []}}
      nil -> {:error, %{reason: "Message not found", log_entries: []}}
    end
  end

  defp upsert_message(messages, msg_id, new_msg) do
    {result, replaced?} =
      Enum.map_reduce(messages, false, fn
        %{message_id: ^msg_id}, _ -> {new_msg, true}
        other, acc -> {other, acc}
      end)

    if replaced?, do: result, else: result ++ [new_msg]
  end

  defp get_base_url(socket) do
    uri = socket.host_uri
    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end
end
