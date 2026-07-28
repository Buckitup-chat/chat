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
        peer_rows = Enum.filter(keys, &(&1["peer_hash"] == user.user_hash))
        {contacts, msg_logs} = scan_peer_rows(user.crypt_skey, peer_rows, base_url)
        {:ok, %{contacts: contacts, log_entries: key_logs ++ msg_logs}}

      {:error, _} = error ->
        error
    end
  end

  defp scan_peer_rows(crypt_skey, peer_rows, base_url) do
    Enum.reduce(peer_rows, {%{}, []}, fn row, {contacts, logs} ->
      peer_hash = row["sender_hash"]

      with {:ok, peer_key} <- unwrap_peer_key(row, crypt_skey),
           {:ok, %{messages: messages, log_entries: msg_logs}} <-
             DialogApi.fetch_dialog_messages(row["dialog_hash"], base_url),
           key when is_binary(key) <- find_review_list_key(messages, peer_hash, peer_key) do
        {Map.put(contacts, peer_hash, key), logs ++ msg_logs}
      else
        {:error, %{log_entries: err_logs}} -> {contacts, logs ++ err_logs}
        _ -> {contacts, logs}
      end
    end)
  end

  defp unwrap_peer_key(row, crypt_skey) do
    with kem_wrap when is_binary(kem_wrap) <-
           Crypto.decode_binary_field(row["peer_kem_wrap_key_b64"]),
         wrapped when is_binary(wrapped) <-
           Crypto.decode_binary_field(row["peer_wrapped_msg_key_b64"]) do
      {:ok, Crypto.unwrap_peer_key(kem_wrap, wrapped, crypt_skey)}
    end
  end

  defp find_review_list_key(messages, peer_hash, peer_key) do
    keys_cache = %{peer_hash => peer_key}

    messages
    |> Enum.filter(&(&1["sender_hash"] == peer_hash))
    |> Enum.find_value(fn msg ->
      case Crypto.decrypt_single_message(msg, keys_cache) do
        %{content: {:review_list_key, %{key_b64: key_b64}}} ->
          case Base.decode64(key_b64, padding: false) do
            {:ok, decoded} -> decoded
            :error -> nil
          end

        _ ->
          nil
      end
    end)
  end
end
