defmodule Chat.Data.Dialog.Guards do
  @moduledoc """
  Membership and self-action guards for dialog rows.

  A user is a participant of a dialog once they have a `dialog_keys` row in it.
  Key rows are bound to their `(sender_hash, peer_hash)` pair by
  `DialogKey.create_changeset/2`, so only the two participants can have one.

  `check_*` return `:ok | {:error, reason}` (HTTP ingestion);
  `validate_*` add errors to a changeset (peer sync).
  """

  import Ecto.Changeset, only: [add_error: 3]

  alias Chat.Data.Dialog
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage

  @not_participant "not a dialog participant"
  @foreign_message "message belongs to another dialog"

  # The poster must have published their own dialog_key first, otherwise the peer
  # has no way to unwrap the poster's sender_msg_key and decrypt what they post.
  def check_dialog_key_published(dialog_hash, sender_hash) do
    if participant?(dialog_hash, sender_hash),
      do: :ok,
      else: {:error, "dialog_key required before posting to dialog"}
  end

  def check_participant(dialog_hash, user_hash) do
    if participant?(dialog_hash, user_hash), do: :ok, else: {:error, @not_participant}
  end

  def check_message_in_dialog(message_id, dialog_hash) do
    if foreign_message?(message_id, dialog_hash), do: {:error, @foreign_message}, else: :ok
  end

  def check_not_self_reaction(message_id, reactor_hash) do
    if message_authored_by?(message_id, reactor_hash),
      do: {:error, "cannot react to own message"},
      else: :ok
  end

  def check_not_self_receipt(message_id, peer_hash) do
    if message_authored_by?(message_id, peer_hash),
      do: {:error, "cannot receipt own message"},
      else: :ok
  end

  def validate_participant(changeset, field, dialog_hash, user_hash) do
    if participant?(dialog_hash, user_hash),
      do: changeset,
      else: add_error(changeset, field, @not_participant)
  end

  def validate_message_in_dialog(changeset, message_id, dialog_hash) do
    if foreign_message?(message_id, dialog_hash),
      do: add_error(changeset, :message_id, @foreign_message),
      else: changeset
  end

  def validate_not_self_reaction(changeset, message_id, reactor_hash) do
    if message_authored_by?(message_id, reactor_hash),
      do: add_error(changeset, :reactor_hash, "cannot react to own message"),
      else: changeset
  end

  def validate_not_self_receipt(changeset, message_id, peer_hash) do
    if message_authored_by?(message_id, peer_hash),
      do: add_error(changeset, :peer_hash, "cannot receipt own message"),
      else: changeset
  end

  defp participant?(dialog_hash, user_hash) do
    is_binary(dialog_hash) and is_binary(user_hash) and
      match?(%DialogKey{}, Dialog.get_dialog_key(dialog_hash, user_hash))
  end

  # Reactions and receipts may arrive before their message; only a known
  # message can be checked.
  defp foreign_message?(message_id, dialog_hash) do
    case message_id && Dialog.get_message(message_id) do
      %DialogMessage{dialog_hash: ^dialog_hash} -> false
      %DialogMessage{} -> true
      _ -> false
    end
  end

  defp message_authored_by?(message_id, actor_hash) do
    case message_id && Dialog.get_message(message_id) do
      %DialogMessage{sender_hash: ^actor_hash} -> true
      _ -> false
    end
  end
end
