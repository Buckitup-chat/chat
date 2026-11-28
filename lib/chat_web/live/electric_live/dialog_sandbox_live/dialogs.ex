defmodule ChatWeb.ElectricLive.DialogSandboxLive.Dialogs do
  @moduledoc """
  Identity import and dialog list of the dialog sandbox: importing the key file,
  listing dialogs and peers, creating and selecting a dialog.
  """

  import ChatWeb.LiveHelpers, only: [public_url: 1]
  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3]

  alias ChatWeb.ElectricLive.DialogSandboxLive.{ApiClient, Crypto, Keys, Streams}
  alias ChatWeb.ElectricLive.IdentityCheck

  @doc "Imports the uploaded identity key file."
  def import_keys(socket) do
    results =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case results do
      [] ->
        assign(socket, :error_message, "No key file selected")

      [result] ->
        import_key_result(socket, result)
    end
  end

  defp import_key_result(socket, result) do
    case Crypto.parse_and_validate_identity(result) do
      {:ok, user_data} ->
        socket
        |> assign(:user, IdentityCheck.mark_on_server(user_data, public_url(socket)))
        |> assign(:dialogs, [])
        |> assign(:selected_dialog, nil)
        |> assign(:messages, [])
        |> assign(:msg_keys_cache, %{})
        |> assign(:error_message, nil)
        |> fetch_available_peers(user_data.user_hash)

      {:error, reason} ->
        assign(socket, :error_message, "Import failed: #{reason}")
    end
  end

  @doc "Loads the user's dialogs from their dialog keys, then refreshes peers."
  def fetch_dialogs(socket) do
    base_url = public_url(socket)
    user_hash = socket.assigns.user.user_hash

    socket =
      case ApiClient.fetch_dialog_keys(user_hash, base_url, Keys.auth(socket)) do
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

    fetch_available_peers(socket, user_hash)
  end

  defp fetch_available_peers(socket, my_hash) do
    base_url = public_url(socket)

    case ApiClient.fetch_all_user_cards(base_url, Keys.auth(socket)) do
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

  @doc "Publishes the own dialog key for `peer_hash` and selects the new dialog."
  def create_dialog(socket, peer_hash) do
    %{user: user} = socket.assigns
    base_url = public_url(socket)

    socket = assign(socket, :operation_in_progress, true)

    with {:ok, %{card: card, log_entries: card_logs}} <-
           ApiClient.fetch_user_card(peer_hash, base_url, Keys.auth(socket)),
         peer_crypt_pkey <- Crypto.decode_binary_field(card["crypt_pkey"]),
         {:ok, %{dialog_hash: dialog_hash, log_entries: key_logs}} <-
           ApiClient.publish_dialog_key(user, peer_hash, peer_crypt_pkey, base_url) do
      dialog = %{dialog_hash: dialog_hash, peer_hash: peer_hash}

      socket
      |> update(:dialogs, &[dialog | &1])
      |> assign(:selected_dialog, dialog_hash)
      |> assign(:peer_hash_input, "")
      |> assign(:operation_in_progress, false)
      |> update(:request_log, &(&1 ++ card_logs ++ key_logs))
    else
      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(:error_message, reason)
        |> assign(:operation_in_progress, false)
        |> update(:request_log, &(&1 ++ logs))
    end
  end

  @doc "Selects a dialog: resets its state, seeds the key cache and starts the streams."
  def select_dialog(socket, hash, peer_hash) do
    %{user: user} = socket.assigns
    base_url = public_url(socket)

    my_key =
      Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)

    keys_cache =
      %{user.user_hash => my_key}
      |> Keys.maybe_unwrap_peer_key(peer_hash, user, base_url, Keys.auth(socket))

    socket
    |> assign(:selected_dialog, hash)
    |> assign(:messages, [])
    |> assign(:refs_tails, %{})
    |> assign(:reactions, %{})
    |> assign(:receipts, %{})
    |> assign(:msg_keys_cache, keys_cache)
    |> Streams.start_dialog_stream(hash)
  end

  @doc "Restarts the streams of the selected dialog."
  def refresh_messages(socket) do
    dialog =
      Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == socket.assigns.selected_dialog))

    case dialog do
      nil -> socket
      d -> Streams.start_dialog_stream(socket, d.dialog_hash)
    end
  end
end
