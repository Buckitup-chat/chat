defmodule ChatWeb.ElectricLive.ReviewSandboxLive.ListPassword do
  @moduledoc """
  Keeps the author's `review_list_password` in `user_storage`.

  The password never rotates — "shared once, shared forever" (docs/pq/reqs/reviews/pq_review_contacts.done.md
  "Key lifetime") — so this is write-once: read the slot, and generate + insert only
  when it is empty. No version chain, no update path.

  `user_storage` reads are public (docs/pq/reqs/pq_user_storage.md §4.1), so the row holds
  ciphertext only: AES-256-GCM under a key derived from the author's own `crypt_skey`.
  """

  import ChatWeb.ElectricLive.ReviewSandboxLive.Http

  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Types.UserStorageSignHash
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.ShapeReader
  alias EnigmaPq

  # Well-known slot for the review_list_password. `user_storage.uuid` is a real
  # Postgres uuid column, so the slot is a fixed UUID — not a label like the
  # frontend's local-only "profile" / "contacts" keys.
  @slot_uuid "b7e9a1c4-3f52-4d18-9a06-2f5c8e0d7141"

  @hkdf_salt "buckitup/user-storage/v1"
  @hkdf_info "review-list-password"

  @doc """
  Returns the author's `review_list_password`, storing a fresh one on first use.

  - `{:ok, password, log_entries}` — `log_entries` is empty when the slot already existed
  - `{:error, %{reason: reason, log_entries: log_entries}}`
  """
  def load_or_create(author, base_url) do
    case fetch(author, base_url) do
      {:ok, password} -> {:ok, password, []}
      :empty -> create(author, base_url)
      {:error, reason} -> {:error, %{reason: reason, log_entries: []}}
    end
  end

  @doc "The fixed `user_storage.uuid` slot this module reads and writes."
  def slot_uuid, do: @slot_uuid

  # --- Read ---

  @doc """
  Reads the author's `review_list_password` without creating one.

  For read-only callers (e.g. browsing a contact's reviews) that must not mint a
  password as a side effect of import. Returns `{:ok, password}`, `:empty`, or
  `{:error, reason}`.
  """
  def fetch(author, base_url) do
    base_url
    |> ShapeReader.rows("user_storage", UserStorage, "user_hash = $1 AND uuid = $2", [
      author.user_hash,
      @slot_uuid
    ])
    |> Enum.reject(& &1.deleted_flag)
    |> case do
      [] -> :empty
      entries -> decrypt_latest(entries, author)
    end
  end

  defp decrypt_latest(entries, author) do
    entries
    |> Enum.max_by(& &1.owner_timestamp)
    |> Map.fetch!(:value_b64)
    |> decode_binary()
    |> EnigmaPq.aes_gcm_decrypt(storage_key(author))
    |> case do
      password when is_binary(password) -> {:ok, password}
      _ -> {:error, "stored review_list_password could not be decrypted"}
    end
  end

  # The shapes endpoint hands back unpadded base64 for bytea; tolerate a raw binary
  # in case a value ever arrives already decoded.
  defp decode_binary(value) do
    case Base.decode64(value, padding: false) do
      {:ok, decoded} -> decoded
      :error -> value
    end
  end

  # --- Write ---

  defp create(author, base_url) do
    password = :crypto.strong_rand_bytes(32)
    entry = new_storage_entry(author, password)
    payload = %{"mutations" => [insert_mutation(entry, author.sign_skey)]}

    with {:ok, ch, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <- post_ingest(ch, payload, author.sign_skey, base_url) do
      {:ok, password, [log1, log2]}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  defp new_storage_entry(author, password) do
    %UserStorage{
      user_hash: author.user_hash,
      uuid: @slot_uuid,
      value_b64: EnigmaPq.aes_gcm_encrypt(password, storage_key(author)),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: TimeKeeper.now_unix()
    }
  end

  # Serialized from the signed struct so the row on the wire cannot drift from what
  # `sign_b64` covers.
  defp insert_mutation(%UserStorage{} = entry, sign_skey) do
    {sign_b64, sign_hash} = sign_struct(entry, sign_skey, UserStorageSignHash)

    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => entry.user_hash,
        "uuid" => entry.uuid,
        "value_b64" => encode_base64(entry.value_b64),
        "deleted_flag" => entry.deleted_flag,
        "parent_sign_hash" => entry.parent_sign_hash,
        "owner_timestamp" => entry.owner_timestamp,
        "sign_b64" => encode_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "user_storage"}
    }
  end

  # --- Shared ---

  # Mirrors the frontend's deriveKeyFromCryptSkey: HKDF-SHA3-256 over the author's own
  # crypt_skey, domain-separated per slot (docs/pq/invariants/09_symmetric_keys.md).
  defp storage_key(%{crypt_skey: crypt_skey}),
    do: EnigmaPq.hkdf_derive(crypt_skey, @hkdf_salt, @hkdf_info, 32)
end
