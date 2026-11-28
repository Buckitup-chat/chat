defmodule ChatWeb.ElectricLive.DialogSandboxLive.ApiClient do
  @moduledoc """
  API client for dialog Electric ingest/shape operations with request logging.
  All reads go through Electric shape endpoints — no direct Ecto queries.

  Facade over `ApiClient.Fetch` (shape reads), `ApiClient.KeyPublish`,
  `ApiClient.MessagePublish`, `ApiClient.ReactionPublish` (ingest writes) and
  `ApiClient.LiveStream` (live shape streams).
  """

  alias ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.Fetch
  alias ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.KeyPublish
  alias ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.LiveStream
  alias ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.MessagePublish
  alias ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.ReactionPublish

  defdelegate fetch_all_user_cards(base_url, auth), to: Fetch
  defdelegate fetch_user_card(user_hash, base_url, auth), to: Fetch
  defdelegate fetch_dialog_keys(user_hash, base_url, auth), to: Fetch
  defdelegate fetch_dialog_keys_by_dialog(dialog_hash, base_url, auth), to: Fetch
  defdelegate fetch_dialog_messages(dialog_hash, base_url, auth), to: Fetch
  defdelegate fetch_message_versions(message_id, base_url, auth), to: Fetch
  defdelegate fetch_reactions(dialog_hash, base_url, auth), to: Fetch
  defdelegate fetch_receipts(dialog_hash, base_url, auth), to: Fetch

  defdelegate publish_dialog_key(user, peer_hash, peer_crypt_pkey, base_url), to: KeyPublish

  defdelegate publish_dialog_message(user, dialog_hash, plaintext, refs_tails, base_url),
    to: MessagePublish

  defdelegate publish_edit_message(
                user,
                dialog_hash,
                message_id,
                current_sign_hash,
                new_plaintext,
                refs_tails,
                base_url
              ),
              to: MessagePublish

  defdelegate publish_delete_message(
                user,
                dialog_hash,
                message_id,
                current_sign_hash,
                refs_tails,
                base_url
              ),
              to: MessagePublish

  defdelegate publish_reaction(
                user,
                dialog_hash,
                message_id,
                message_sign_hash,
                emoji,
                peer_hash,
                base_url
              ),
              to: ReactionPublish

  defdelegate delete_reaction(user, existing_reaction, peer_hash, base_url), to: ReactionPublish

  defdelegate publish_receipt(user, dialog_hash, message_id, message_sign_hash, type, base_url),
    to: ReactionPublish

  defdelegate start_message_stream(dialog_hash, base_url, subscriber_pid, auth), to: LiveStream
  defdelegate start_reaction_stream(dialog_hash, base_url, subscriber_pid, auth), to: LiveStream
  defdelegate start_receipt_stream(dialog_hash, base_url, subscriber_pid, auth), to: LiveStream
end
