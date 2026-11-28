defmodule ChatWeb.ElectricLive.DialogSandboxLive.Keys do
  @moduledoc """
  Dialog key handling for the dialog sandbox: publishes the own dialog key when
  missing and fills the per-sender message key cache by unwrapping peer keys
  fetched over the Electric HTTP API.
  """

  import ChatWeb.LiveHelpers, only: [public_url: 1]
  import Phoenix.Component, only: [assign: 3, update: 3]

  alias Chat.Data.Types.DialogHash
  alias ChatWeb.ElectricLive.DialogSandboxLive.{ApiClient, Crypto}

  @doc "Auth credentials of the imported user, used for gated shape reads."
  def auth(socket) do
    %{user_hash: socket.assigns.user.user_hash, sign_skey: socket.assigns.user.sign_skey}
  end

  @doc "Makes sure the user's own dialog key row exists, publishing it when missing."
  def ensure_dialog_key(socket, user, peer_hash, base_url) do
    dialog_hash = DialogHash.for_pair(user.user_hash, peer_hash)
    auth = auth(socket)

    case ApiClient.fetch_dialog_keys_by_dialog(dialog_hash, base_url, auth) do
      {:ok, %{keys: keys, log_entries: logs}} ->
        socket = update(socket, :request_log, &(&1 ++ logs))
        has_own_key = Enum.any?(keys, &(&1["sender_hash"] == user.user_hash))

        if has_own_key,
          do: {:ok, socket},
          else: publish_own_dialog_key(socket, user, peer_hash, base_url, auth)

      {:error, _} = error ->
        error
    end
  end

  defp publish_own_dialog_key(socket, user, peer_hash, base_url, auth) do
    with {:ok, %{card: card, log_entries: card_logs}} <-
           ApiClient.fetch_user_card(peer_hash, base_url, auth),
         peer_crypt_pkey = Crypto.decode_binary_field(card["crypt_pkey"]),
         {:ok, %{log_entries: key_logs}} <-
           ApiClient.publish_dialog_key(user, peer_hash, peer_crypt_pkey, base_url) do
      {:ok, update(socket, :request_log, &(&1 ++ card_logs ++ key_logs))}
    end
  end

  @doc "Adds message keys for every sender of `raw_msgs` not yet in the cache."
  def ensure_sender_keys(socket, raw_msgs) do
    %{user: user, dialogs: dialogs, selected_dialog: selected_dialog} = socket.assigns
    base_url = public_url(socket)
    auth = auth(socket)
    dialog = Enum.find(dialogs, &(&1.dialog_hash == selected_dialog))

    raw_msgs
    |> Enum.map(& &1["sender_hash"])
    |> Enum.uniq()
    |> Enum.reject(&Map.has_key?(socket.assigns.msg_keys_cache, &1))
    |> Enum.reduce(socket, fn sender_hash, socket ->
      keys_cache =
        if sender_hash == user.user_hash && dialog do
          my_key =
            Crypto.derive_sender_msg_key(
              user.sign_skey,
              user.crypt_skey,
              user.contact_skey,
              dialog.peer_hash
            )

          Map.put(socket.assigns.msg_keys_cache, user.user_hash, my_key)
        else
          maybe_unwrap_peer_key(socket.assigns.msg_keys_cache, sender_hash, user, base_url, auth)
        end

      assign(socket, :msg_keys_cache, keys_cache)
    end)
  end

  @doc "Unwraps the peer's message key into the cache, leaving the cache as is on failure."
  def maybe_unwrap_peer_key(keys_cache, peer_hash, user, base_url, auth) do
    if Map.has_key?(keys_cache, peer_hash) do
      keys_cache
    else
      dialog_hash = DialogHash.for_pair(user.user_hash, peer_hash)

      with {:ok, %{keys: keys}} <-
             ApiClient.fetch_dialog_keys_by_dialog(dialog_hash, base_url, auth),
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
end
