defmodule ChatWeb.ElectricLive.DialogSandboxLive.Reactions do
  @moduledoc """
  Emoji reactions of the selected dialog: toggling the own reaction and folding
  the reaction stream into reactions grouped by message sign hash.
  """

  import ChatWeb.LiveHelpers, only: [public_url: 1]
  import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]

  alias ChatWeb.ElectricLive.DialogSandboxLive.{ApiClient, Crypto, Keys}

  @doc "Adds the own reaction, or removes it when already set."
  def react(socket, {_msg_id, _sign_hash, _emoji} = reaction) do
    %{user: user, selected_dialog: dialog_hash} = socket.assigns
    dialog = Enum.find(socket.assigns.dialogs, &(&1.dialog_hash == dialog_hash))
    base_url = public_url(socket)

    case Keys.ensure_dialog_key(socket, user, dialog.peer_hash, base_url) do
      {:ok, socket} -> toggle_reaction(socket, dialog, reaction, base_url)
      {:error, %{reason: reason, log_entries: logs}} -> report_error(socket, reason, logs)
    end
  end

  defp toggle_reaction(socket, dialog, {_msg_id, sign_hash, emoji} = reaction, base_url) do
    %{user: user, reactions: reactions} = socket.assigns

    existing =
      reactions
      |> Map.get(sign_hash, [])
      |> Enum.find(&(&1.emoji == emoji and &1.reactor_hash == user.user_hash))

    case send_reaction(existing, user, dialog, reaction, base_url) do
      {:ok, %{log_entries: logs}} ->
        socket
        |> update(:reactions, &update_own_reaction(&1, existing, user, dialog, reaction))
        |> update(:request_log, &(&1 ++ logs))

      {:error, %{reason: reason, log_entries: logs}} ->
        report_error(socket, reason, logs)
    end
  end

  defp send_reaction(nil, user, dialog, {msg_id, sign_hash, emoji}, base_url) do
    ApiClient.publish_reaction(
      user,
      dialog.dialog_hash,
      msg_id,
      sign_hash,
      emoji,
      dialog.peer_hash,
      base_url
    )
  end

  defp send_reaction(existing, user, dialog, _reaction, base_url),
    do: ApiClient.delete_reaction(user, existing, dialog.peer_hash, base_url)

  defp update_own_reaction(rxns, nil, user, dialog, {msg_id, sign_hash, emoji}) do
    new_reaction = %{
      reaction_hash: reaction_hash_for(user, dialog.peer_hash, msg_id, emoji),
      dialog_hash: dialog.dialog_hash,
      message_id: msg_id,
      message_sign_hash: sign_hash,
      reactor_hash: user.user_hash,
      emoji: emoji,
      deleted_flag: false
    }

    Map.update(rxns, sign_hash, [new_reaction], &(&1 ++ [new_reaction]))
  end

  defp update_own_reaction(rxns, existing, _user, _dialog, {_msg_id, sign_hash, _emoji}) do
    Map.update(rxns, sign_hash, [], fn list ->
      Enum.reject(list, &(&1.reaction_hash == existing.reaction_hash))
    end)
  end

  defp reaction_hash_for(user, peer_hash, message_id, emoji) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)

    Crypto.compute_reaction_hash(sender_msg_key, message_id, user.user_hash, emoji)
  end

  defp report_error(socket, reason, logs) do
    socket
    |> assign(:error_message, reason)
    |> update(:request_log, &(&1 ++ logs))
  end

  @doc "Initial stream load: unwraps reactor keys and groups reactions by message."
  def loaded(socket, raw_reactions) do
    %{msg_keys_cache: keys_cache, user: user} = socket.assigns
    base_url = public_url(socket)
    auth = Keys.auth(socket)

    keys_cache =
      raw_reactions
      |> Enum.map(& &1["reactor_hash"])
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(keys_cache, &1))
      |> Enum.reduce(keys_cache, &Keys.maybe_unwrap_peer_key(&2, &1, user, base_url, auth))

    reactions = Crypto.group_reactions_by_message(raw_reactions, keys_cache)
    assign(socket, reactions: reactions, msg_keys_cache: keys_cache)
  end

  @doc "Applies a streamed reaction insert, update or soft delete."
  def changed(socket, raw) do
    %{msg_keys_cache: keys_cache, user: user} = socket.assigns
    base_url = public_url(socket)
    auth = Keys.auth(socket)

    keys_cache =
      if Map.has_key?(keys_cache, raw["reactor_hash"]) do
        keys_cache
      else
        Keys.maybe_unwrap_peer_key(keys_cache, raw["reactor_hash"], user, base_url, auth)
      end

    decrypted = Crypto.decrypt_single_reaction(raw, keys_cache)

    reactions =
      if decrypted.deleted_flag do
        Map.update(socket.assigns.reactions, decrypted.message_sign_hash, [], fn list ->
          Enum.reject(list, &(&1.reaction_hash == decrypted.reaction_hash))
        end)
      else
        Map.update(
          socket.assigns.reactions,
          decrypted.message_sign_hash,
          [decrypted],
          &upsert_reaction(&1, decrypted)
        )
      end

    assign(socket, reactions: reactions, msg_keys_cache: keys_cache)
  end

  defp upsert_reaction(list, reaction) do
    case Enum.find_index(list, &(&1.reaction_hash == reaction.reaction_hash)) do
      nil -> list ++ [reaction]
      idx -> List.replace_at(list, idx, reaction)
    end
  end
end
