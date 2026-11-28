defmodule ChatWeb.ElectricLive.DialogSandboxLive.Messages do
  @moduledoc """
  Messages of the selected dialog: sending, editing and deleting own messages,
  and folding the message stream into decrypted messages.
  """

  import ChatWeb.LiveHelpers, only: [public_url: 1]
  import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]

  alias ChatWeb.ElectricLive.DialogSandboxLive.{ApiClient, Crypto, Keys, Streams, Versions}

  @doc "Publishes a new message, publishing the own dialog key first when missing."
  def send_message(socket, text) do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    dialog = Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == dialog_hash))
    base_url = public_url(socket)
    refs_tails = %{peer_hash: dialog.peer_hash, tails: socket.assigns.refs_tails}

    socket = assign(socket, :operation_in_progress, true)

    with {:ok, socket} <- Keys.ensure_dialog_key(socket, user, dialog.peer_hash, base_url),
         {:ok, %{message_id: msg_id, sign_hash: sign_hash, log_entries: logs}} <-
           ApiClient.publish_dialog_message(user, dialog_hash, text, refs_tails, base_url) do
      socket
      |> assign(:compose_text, "")
      |> assign(:refs_tails, %{msg_id => sign_hash})
      |> assign(:operation_in_progress, false)
      |> update(:request_log, &(&1 ++ logs))
      |> Streams.maybe_start_stream(dialog_hash)
    else
      {:error, %{reason: reason, log_entries: logs}} -> fail(socket, reason, logs)
    end
  end

  @doc "Publishes a new version of an own message."
  def save_edit(socket, msg_id, text) do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    dialog = Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == dialog_hash))
    base_url = public_url(socket)
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
      socket
      |> assign(:editing_message_id, nil)
      |> assign(:operation_in_progress, false)
      |> assign(:refs_tails, %{msg_id => new_sign_hash})
      |> update(:request_log, &(&1 ++ logs))
    else
      {:error, %{reason: reason, log_entries: logs}} -> fail(socket, reason, logs)
    end
  end

  @doc "Publishes the deletion of an own message."
  def delete_message(socket, msg_id) do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    dialog = Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == dialog_hash))
    base_url = public_url(socket)
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
      socket
      |> assign(:operation_in_progress, false)
      |> update(:request_log, &(&1 ++ logs))
    else
      {:error, %{reason: reason, log_entries: logs}} -> fail(socket, reason, logs)
    end
  end

  defp fail(socket, reason, logs) do
    socket
    |> assign(:error_message, reason)
    |> assign(:operation_in_progress, false)
    |> update(:request_log, &(&1 ++ logs))
  end

  defp find_own_message(messages, msg_id, user_hash) do
    case Enum.find(messages, &(&1.message_id == msg_id)) do
      %{sender_hash: ^user_hash} = msg -> {:ok, msg}
      %{} -> {:error, %{reason: "Can only modify own messages", log_entries: []}}
      nil -> {:error, %{reason: "Message not found", log_entries: []}}
    end
  end

  @doc "Initial stream load: keeps the latest version of each message, decrypted."
  def loaded(socket, raw_msgs) do
    sorted =
      raw_msgs
      |> Enum.group_by(& &1["message_id"])
      |> Map.values()
      |> Enum.map(fn versions -> Enum.max_by(versions, & &1["owner_timestamp"]) end)
      |> Enum.sort_by(& &1["message_id"])

    socket = Keys.ensure_sender_keys(socket, sorted)
    keys_cache = socket.assigns.msg_keys_cache
    messages = Enum.map(sorted, &Crypto.decrypt_single_message(&1, keys_cache))
    tails = Crypto.compute_tails(sorted, keys_cache)

    assign(socket, messages: messages, refs_tails: tails, sync_status: :loaded)
  end

  @doc "Appends a newly streamed message unless it is already listed."
  def new_message(socket, raw_msg) do
    already_exists =
      Enum.any?(socket.assigns.messages, &(&1.message_id == raw_msg["message_id"]))

    if already_exists do
      socket
    else
      socket = Keys.ensure_sender_keys(socket, [raw_msg])
      msg = Crypto.decrypt_single_message(raw_msg, socket.assigns.msg_keys_cache)

      socket
      |> update(:messages, &(&1 ++ [msg]))
      |> assign(:refs_tails, %{raw_msg["message_id"] => raw_msg["sign_hash"]})
    end
  end

  @doc "Replaces a message with its streamed update."
  def updated_message(socket, raw_msg) do
    msg_id = raw_msg["message_id"]
    socket = Keys.ensure_sender_keys(socket, [raw_msg])
    decrypted = Crypto.decrypt_single_message(raw_msg, socket.assigns.msg_keys_cache)

    socket
    |> update(:messages, &upsert_message(&1, msg_id, decrypted))
    |> update(:refs_tails, &Map.put(&1, msg_id, raw_msg["sign_hash"]))
    |> Versions.refresh_if_expanded(msg_id)
  end

  defp upsert_message(messages, msg_id, new_msg) do
    {result, replaced?} =
      Enum.map_reduce(messages, false, fn
        %{message_id: ^msg_id}, _ -> {new_msg, true}
        other, acc -> {other, acc}
      end)

    if replaced?, do: result, else: result ++ [new_msg]
  end
end
