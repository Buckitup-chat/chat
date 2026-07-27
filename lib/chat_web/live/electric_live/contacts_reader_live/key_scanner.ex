defmodule ChatWeb.ElectricLive.ContactsReaderLive.KeyScanner do
  @moduledoc """
  Scans the reader's dialogs for `review_list_key` messages.

  For each dialog the reader participates in, fetches messages, decrypts them,
  and extracts `review_list_key` content types to build a
  `peer_user_hash -> review_list_password` map.
  """

  alias ChatWeb.ElectricLive.DialogSandboxLive.ApiClient, as: DialogApi
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto

  @doc "Returns `{:ok, %{contacts: map, log_entries: list}}` or `{:error, ...}`."
  def scan(user, base_url) do
    case DialogApi.fetch_dialog_keys(user.user_hash, base_url) do
      {:ok, %{keys: keys, log_entries: key_logs}} ->
        dialogs = Crypto.build_dialog_list(keys, user.user_hash)
        {contacts, msg_logs} = scan_dialogs(user, dialogs, keys, base_url)
        {:ok, %{contacts: contacts, log_entries: key_logs ++ msg_logs}}

      {:error, _} = error ->
        error
    end
  end

  defp scan_dialogs(user, dialogs, all_keys, base_url) do
    dialogs
    |> Enum.reduce({%{}, []}, fn dialog, {contacts, logs} ->
      case scan_one_dialog(user, dialog, all_keys, base_url) do
        {:ok, key, new_logs} ->
          {Map.put(contacts, dialog.peer_hash, key), logs ++ new_logs}

        :no_key ->
          {contacts, logs}

        {:error, new_logs} ->
          {contacts, logs ++ new_logs}
      end
    end)
  end

  defp scan_one_dialog(user, dialog, all_keys, base_url) do
    keys_cache = build_keys_cache(user, dialog, all_keys, base_url)

    with {:ok, %{messages: messages, log_entries: logs}} <-
           DialogApi.fetch_dialog_messages(dialog.dialog_hash, base_url),
         key when is_binary(key) <-
           extract_review_list_key(messages, keys_cache, dialog.peer_hash) do
      {:ok, key, logs}
    else
      nil -> :no_key
      {:error, %{log_entries: logs}} -> {:error, logs}
    end
  end

  defp extract_review_list_key(messages, keys_cache, peer_hash) do
    case keys_cache do
      %{^peer_hash => peer_key} ->
        messages
        |> Enum.filter(&(&1["sender_hash"] == peer_hash))
        |> Enum.find_value(&decrypt_review_list_key(&1, peer_key))

      _ ->
        nil
    end
  end

  defp decrypt_review_list_key(msg, peer_key) do
    with blob when is_binary(blob) <- msg["content_b64"],
         plaintext when is_binary(plaintext) <-
           EnigmaPq.aes_gcm_decrypt(Crypto.decode_binary_field(blob), peer_key),
         {:ok, %{"review_list_key" => [key_b64]}} <- Jason.decode(plaintext),
         {:ok, decoded} <- Base.decode64(key_b64, padding: false) do
      decoded
    else
      _ -> nil
    end
  end

  defp build_keys_cache(user, dialog, all_keys, base_url) do
    my_key =
      Crypto.derive_sender_msg_key(
        user.sign_skey,
        user.crypt_skey,
        user.contact_skey,
        dialog.peer_hash
      )

    cache = %{user.user_hash => my_key}

    with {:find, %{} = row} <-
           {:find,
            Enum.find(all_keys, fn row ->
              row["dialog_hash"] == dialog.dialog_hash and row["sender_hash"] == dialog.peer_hash
            end)},
         kem_wrap when is_binary(kem_wrap) <-
           Crypto.decode_binary_field(row["peer_kem_wrap_key_b64"]),
         wrapped when is_binary(wrapped) <-
           Crypto.decode_binary_field(row["peer_wrapped_msg_key_b64"]) do
      Map.put(cache, dialog.peer_hash, Crypto.unwrap_peer_key(kem_wrap, wrapped, user.crypt_skey))
    else
      {:find, nil} -> cache
      _ -> try_fetch_peer_key(cache, dialog, user, base_url)
    end
  end

  defp try_fetch_peer_key(cache, dialog, user, base_url) do
    with {:ok, %{keys: keys}} <-
           DialogApi.fetch_dialog_keys_by_dialog(dialog.dialog_hash, base_url),
         %{} = row <- Enum.find(keys, &(&1["sender_hash"] == dialog.peer_hash)),
         kem_wrap when is_binary(kem_wrap) <-
           Crypto.decode_binary_field(row["peer_kem_wrap_key_b64"]),
         wrapped when is_binary(wrapped) <-
           Crypto.decode_binary_field(row["peer_wrapped_msg_key_b64"]) do
      Map.put(cache, dialog.peer_hash, Crypto.unwrap_peer_key(kem_wrap, wrapped, user.crypt_skey))
    else
      _ -> cache
    end
  end
end
