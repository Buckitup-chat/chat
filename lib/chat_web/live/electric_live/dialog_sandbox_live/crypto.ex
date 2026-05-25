defmodule ChatWeb.ElectricLive.DialogSandboxLive.Crypto do
  @moduledoc """
  Pure crypto operations for dialog sandbox.
  All functions delegate to EnigmaPq primitives.
  """

  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageReactionHash
  alias Chat.Data.Types.DialogMessageReceiptHash
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.Types.UserHash

  def compute_dialog_hash(user_hash_a, user_hash_b) do
    [a, b] = Enum.sort([user_hash_a, user_hash_b])
    EnigmaPq.hash(a <> b) |> DialogHash.from_binary()
  end

  def derive_sender_msg_key(sign_skey, crypt_skey, contact_skey, peer_user_hash) do
    ikm = sign_skey <> crypt_skey <> contact_skey <> peer_user_hash
    EnigmaPq.hkdf_derive(ikm, "buckitup/dialog-mk/v1", "dialog-mk")
  end

  def wrap_for_peer(sender_msg_key, peer_crypt_pkey) do
    {shared_secret, kem_ct} = EnigmaPq.encapsulate_secret(peer_crypt_pkey)
    wrap_key = EnigmaPq.hkdf_derive(shared_secret, "buckitup/dialog-wrap/v1", "wrap")
    wrapped = EnigmaPq.aes_gcm_encrypt(sender_msg_key, wrap_key)
    {kem_ct, wrapped}
  end

  def unwrap_peer_key(kem_wrap_key, wrapped_msg_key, own_crypt_skey) do
    shared_secret = EnigmaPq.decapsulate_secret(kem_wrap_key, own_crypt_skey)
    wrap_key = EnigmaPq.hkdf_derive(shared_secret, "buckitup/dialog-wrap/v1", "wrap")
    EnigmaPq.aes_gcm_decrypt(wrapped_msg_key, wrap_key)
  end

  def encrypt_content(plaintext, sender_msg_key) do
    EnigmaPq.aes_gcm_encrypt(plaintext, sender_msg_key)
  end

  def decrypt_content(blob, sender_msg_key) do
    EnigmaPq.aes_gcm_decrypt(blob, sender_msg_key)
  end

  def encrypt_refs_map(refs_map, sender_msg_key) do
    refs_map |> Jason.encode!() |> EnigmaPq.aes_gcm_encrypt(sender_msg_key)
  end

  def decrypt_refs_map(nil, _key), do: %{}
  def decrypt_refs_map("", _key), do: %{}
  def decrypt_refs_map(blob, nil), do: try_decode_refs(blob)

  def decrypt_refs_map(blob, key) do
    case decrypt_content(decode_binary_field(blob), key) do
      :error -> %{}
      plaintext -> try_decode_refs(plaintext)
    end
  end

  defp try_decode_refs(data) do
    case Jason.decode(data) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  def compute_tails(messages, keys_cache) do
    all_refs =
      messages
      |> Enum.flat_map(fn msg ->
        key = keys_cache[msg["sender_hash"]]
        refs = decrypt_refs_map(msg["refs_map_b64"], key)
        Map.to_list(refs)
      end)
      |> MapSet.new()

    messages
    |> Enum.reject(fn msg ->
      MapSet.member?(all_refs, {msg["message_id"], msg["sign_hash"]})
    end)
    |> Map.new(&{&1["message_id"], &1["sign_hash"]})
  end

  def compute_sign_hash(sign_b64) do
    sign_b64 |> EnigmaPq.hash() |> DialogMessageSignHash.from_binary()
  end

  def compute_reaction_hash(sender_msg_key, message_id, reactor_hash, emoji_plaintext) do
    (message_id <> reactor_hash <> emoji_plaintext)
    |> then(&EnigmaPq.hmac_sha3_512(sender_msg_key, &1))
    |> DialogMessageReactionHash.from_binary()
  end

  def encrypt_emoji(emoji_plaintext, sender_msg_key) do
    EnigmaPq.aes_gcm_encrypt(emoji_plaintext, sender_msg_key)
  end

  def compute_receipt_hash(message_id, message_sign_hash, peer_hash, type) do
    (message_id <> message_sign_hash <> peer_hash <> type)
    |> EnigmaPq.hash()
    |> DialogMessageReceiptHash.from_binary()
  end

  def decrypt_single_message(msg, keys_cache) do
    sender = msg["sender_hash"]
    key = keys_cache[sender]
    deleted = msg["deleted_flag"] in [true, "true", "t"]

    content =
      case {deleted, key, msg["content_b64"]} do
        {true, _, _} ->
          "[deleted]"

        {_, nil, _} ->
          "[no key]"

        {_, _, v} when v in [nil, ""] ->
          "[empty]"

        {_, k, blob} ->
          case decrypt_content(decode_binary_field(blob), k) do
            :error -> "[decrypt failed]"
            plaintext -> plaintext
          end
      end

    %{
      message_id: msg["message_id"],
      sender_hash: sender,
      content: content,
      owner_timestamp: msg["owner_timestamp"],
      sign_hash: msg["sign_hash"],
      refs_map: decrypt_refs_map(msg["refs_map_b64"], key),
      deleted: deleted,
      parent_sign_hash: msg["parent_sign_hash"]
    }
  end

  def decrypt_single_reaction(raw, keys_cache) do
    reactor = raw["reactor_hash"]
    key = keys_cache[reactor]

    emoji =
      case {key, raw["type_b64"]} do
        {nil, _} ->
          "[no key]"

        {_, v} when v in [nil, ""] ->
          "[empty]"

        {k, blob} ->
          case decrypt_content(decode_binary_field(blob), k) do
            :error -> "[decrypt failed]"
            plaintext -> plaintext
          end
      end

    %{
      reaction_hash: raw["reaction_hash"],
      message_id: raw["message_id"],
      message_sign_hash: raw["message_sign_hash"],
      reactor_hash: reactor,
      emoji: emoji,
      deleted_flag: raw["deleted_flag"] in [true, "true", "t"]
    }
  end

  def group_reactions_by_message(raw_reactions, keys_cache) do
    raw_reactions
    |> Enum.map(&decrypt_single_reaction(&1, keys_cache))
    |> Enum.reject(& &1.deleted_flag)
    |> Enum.group_by(& &1.message_id)
  end

  def group_receipts_by_message(raw_receipts) do
    raw_receipts
    |> Enum.map(fn raw ->
      %{
        message_id: raw["message_id"],
        message_sign_hash: raw["message_sign_hash"],
        peer_hash: raw["peer_hash"],
        type: raw["type"]
      }
    end)
    |> Enum.group_by(& &1.message_id)
  end

  def build_dialog_list(keys, my_hash) do
    keys
    |> Enum.group_by(& &1["dialog_hash"])
    |> Enum.map(fn {dialog_hash, rows} ->
      peer_hash =
        Enum.find_value(rows, fn row ->
          cond do
            row["sender_hash"] == my_hash -> row["peer_hash"]
            row["peer_hash"] == my_hash -> row["sender_hash"]
            true -> nil
          end
        end)

      %{dialog_hash: dialog_hash, peer_hash: peer_hash || "unknown"}
    end)
  end

  def decode_binary_field(nil), do: nil

  def decode_binary_field(value) when is_binary(value) do
    case Base.decode64(value, padding: false) do
      {:ok, bin} ->
        bin

      :error ->
        case Base.decode16(value, case: :mixed) do
          {:ok, bin} -> bin
          :error -> value
        end
    end
  end

  @identity_keys ~w(user_hash name sign_pkey sign_skey crypt_pkey crypt_skey
                     crypt_cert contact_pkey contact_skey contact_cert)

  def parse_and_validate_identity(json_string) do
    with {:ok, data} <- Jason.decode(json_string),
         {:ok, _} <- validate_identity_format(data),
         {:ok, keys} <- decode_identity_keys(data),
         :ok <- verify_user_hash(data["user_hash"], keys) do
      {:ok, build_user_data(data, keys)}
    end
  end

  defp validate_identity_format(%{"type" => "buckitup_pq_identity", "version" => 2} = data) do
    case Enum.find(@identity_keys, &(not Map.has_key?(data, &1))) do
      nil -> {:ok, data}
      missing -> {:error, "missing field: #{missing}"}
    end
  end

  defp validate_identity_format(_), do: {:error, "invalid file format"}

  defp decode_identity_keys(data) do
    ~w(sign_pkey sign_skey crypt_pkey crypt_skey crypt_cert contact_pkey contact_skey contact_cert)
    |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, acc} ->
      case Base.decode64(data[field], padding: false) do
        {:ok, bin} -> {:cont, {:ok, Map.put(acc, String.to_existing_atom(field), bin)}}
        :error -> {:halt, {:error, "invalid base64 in #{field}"}}
      end
    end)
  end

  defp verify_user_hash(user_hash, keys) do
    expected = keys.sign_pkey |> EnigmaPq.hash() |> UserHash.from_binary()
    if user_hash == expected, do: :ok, else: {:error, "user_hash does not match sign_pkey"}
  end

  defp build_user_data(data, keys) do
    keys
    |> Map.put(:user_hash, data["user_hash"])
    |> Map.put(:name, data["name"])
    |> Map.put(:owner_timestamp, data["owner_timestamp"] || 0)
  end
end
