defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Contacts do
  @moduledoc """
  Delivers the author's `review_list_password` to chosen peers.

  The sandbox has no contact list of its own, so "contacts" here is whoever the
  author picks out of the `user_cards` directory. Delivery is an ordinary dialog
  message carrying the `review_list_key` content type — `pq_dialogs.done` already
  wraps every message with `sender_msg_key` + ML-KEM-1024, so the key is
  protected exactly as any other content and nothing new is needed
  cryptographically.

  Nothing is stored on receipt yet: mapping `peer_user_hash → review_list_password`
  into a contact record is Phase 3 client state.
  """

  alias ChatWeb.ElectricLive.DialogSandboxLive.ApiClient, as: DialogApi
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto

  @doc "Peers the author can share with — everyone else with a live card."
  def list_peers(author, base_url) do
    case DialogApi.fetch_all_user_cards(base_url) do
      {:ok, %{cards: cards, log_entries: logs}} ->
        peers =
          cards
          |> Enum.reject(&(&1["user_hash"] == author.user_hash or deleted?(&1)))
          |> Enum.map(&%{user_hash: &1["user_hash"], name: &1["name"]})
          |> Enum.sort_by(& &1.name)

        {:ok, %{peers: peers, log_entries: logs}}

      {:error, failure} ->
        {:error, failure}
    end
  end

  # These are raw shape rows, not Ecto-parsed ones, so booleans arrive as
  # strings — and both `"false"` and `"f"` occur in practice. Testing the value
  # for truthiness would reject every card.
  defp deleted?(card), do: card["deleted_flag"] in [true, "true", "t"]

  @doc """
  Sends the key to each peer, collecting who it reached and every log entry.

  One peer failing does not stop the others — `error_message` is nil unless some
  delivery failed, and `sent` lists what actually landed.
  """
  def send_key(author, peer_hashes, base_url) do
    content = key_content(author.review_list_password)

    peer_hashes
    |> Enum.reduce(%{sent: [], failed: [], log_entries: []}, fn peer_hash, acc ->
      case send_to_peer(author, peer_hash, content, base_url) do
        {:ok, logs} ->
          %{acc | sent: acc.sent ++ [peer_hash], log_entries: acc.log_entries ++ logs}

        {:error, reason, logs} ->
          %{
            acc
            | failed: acc.failed ++ [{peer_hash, reason}],
              log_entries: acc.log_entries ++ logs
          }
      end
    end)
    |> then(&Map.put(&1, :error_message, delivery_error(&1.failed)))
  end

  defp delivery_error([]), do: nil

  defp delivery_error(failed) do
    "Key delivery failed for: " <>
      Enum.map_join(failed, ", ", fn {hash, why} -> "#{hash} (#{why})" end)
  end

  @doc "The `review_list_key` compound content, per the content polymorphism spec."
  def key_content(review_list_password) do
    Jason.encode!(%{"review_list_key" => [Base.encode64(review_list_password, padding: false)]})
  end

  # The dialog_key row is a hard precondition — Dialog.Validation rejects a
  # message from a sender who has not published one, because the peer would have
  # no way to unwrap the sender_msg_key. Re-publishing is an LWW upsert on
  # (dialog_hash, sender_hash), so it is safe to send unconditionally.
  defp send_to_peer(author, peer_hash, content, base_url) do
    with {:ok, crypt_pkey, card_logs} <- peer_crypt_pkey(peer_hash, base_url),
         {:ok, %{dialog_hash: dialog_hash, log_entries: key_logs}} <-
           DialogApi.publish_dialog_key(author, peer_hash, crypt_pkey, base_url),
         {:ok, tails, tail_logs} <- dialog_tails(author, dialog_hash, peer_hash, base_url),
         {:ok, %{log_entries: msg_logs}} <-
           DialogApi.publish_dialog_message(
             author,
             dialog_hash,
             content,
             %{peer_hash: peer_hash, tails: tails},
             base_url
           ) do
      {:ok, card_logs ++ key_logs ++ tail_logs ++ msg_logs}
    else
      {:error, reason, logs} -> {:error, reason, logs}
      {:error, %{reason: reason, log_entries: logs}} -> {:error, reason, logs}
    end
  end

  # fetch_user_card/2 answers {:ok, %{card: nil}} for an unknown hash, which
  # would otherwise blow up inside EnigmaPq.encapsulate_secret/1.
  defp peer_crypt_pkey(peer_hash, base_url) do
    case DialogApi.fetch_user_card(peer_hash, base_url) do
      {:ok, %{card: nil, log_entries: logs}} ->
        {:error, "no user card for #{peer_hash}", logs}

      {:ok, %{card: card, log_entries: logs}} ->
        {:ok, Crypto.decode_binary_field(card["crypt_pkey"]), logs}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:error, reason, logs}
    end
  end

  # An empty tails map means "genesis". Sending that into a dialog that already
  # has messages would fork the DAG, so read it first. Only the author's own
  # messages are decryptable here; the peer's refs fall back to %{}, which
  # over-includes tails — harmless, unlike under-including them.
  defp dialog_tails(author, dialog_hash, peer_hash, base_url) do
    case DialogApi.fetch_dialog_messages(dialog_hash, base_url) do
      {:ok, %{messages: [], log_entries: logs}} ->
        {:ok, %{}, logs}

      {:ok, %{messages: messages, log_entries: logs}} ->
        keys_cache = %{author.user_hash => sender_msg_key(author, peer_hash)}
        {:ok, Crypto.compute_tails(messages, keys_cache), logs}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:error, reason, logs}
    end
  end

  defp sender_msg_key(author, peer_hash) do
    Crypto.derive_sender_msg_key(
      author.sign_skey,
      author.crypt_skey,
      author.contact_skey,
      peer_hash
    )
  end
end
