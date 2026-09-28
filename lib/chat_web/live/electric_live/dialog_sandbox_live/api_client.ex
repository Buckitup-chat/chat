defmodule ChatWeb.ElectricLive.DialogSandboxLive.ApiClient do
  @moduledoc """
  API client for dialog Electric ingest/shape operations with request logging.
  All reads go through Electric shape endpoints — no direct Ecto queries.
  """

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Schemas.DialogMessageReceipt
  alias Chat.Data.Types.DialogMessageId
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.DialogSandboxLive.Content
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias Electric.Client.Message

  def fetch_all_user_cards(base_url) do
    base_url |> fetch_shape("user_cards") |> wrap_result(:cards)
  end

  def fetch_user_card(user_hash, base_url) do
    case fetch_shape(base_url, "user_cards", "user_hash='#{user_hash}'") do
      {:ok, rows, log} ->
        {:ok, %{card: List.first(rows), log_entries: [log]}}

      {:error, reason, log} ->
        {:error, %{reason: reason, log_entries: [log]}}
    end
  end

  def fetch_dialog_keys(user_hash, base_url) do
    with {:ok, sender_rows, log1} <-
           fetch_shape(base_url, "dialog_keys", "sender_hash::text='#{user_hash}'"),
         {:ok, peer_rows, log2} <-
           fetch_shape(base_url, "dialog_keys", "peer_hash='#{user_hash}'") do
      all_keys =
        (sender_rows ++ peer_rows)
        |> Enum.uniq_by(&{&1["dialog_hash"], &1["sender_hash"]})

      {:ok, %{keys: all_keys, log_entries: [log1, log2]}}
    else
      {:error, reason, log} -> {:error, %{reason: reason, log_entries: [log]}}
    end
  end

  def fetch_dialog_keys_by_dialog(dialog_hash, base_url) do
    base_url |> fetch_shape("dialog_keys", "dialog_hash='#{dialog_hash}'") |> wrap_result(:keys)
  end

  def fetch_dialog_messages(dialog_hash, base_url) do
    base_url
    |> fetch_shape("dialog_messages", "dialog_hash='#{dialog_hash}'")
    |> wrap_result(:messages)
  end

  def fetch_message_versions(message_id, base_url) do
    base_url
    |> fetch_shape("dialog_messages_versions", "message_id='#{message_id}'")
    |> wrap_result(:versions)
  end

  def publish_dialog_key(user, peer_hash, peer_crypt_pkey, base_url) do
    dialog_hash = Crypto.compute_dialog_hash(user.user_hash, peer_hash)

    sender_msg_key =
      Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)

    {kem_wrap_key, wrapped_msg_key} = Crypto.wrap_for_peer(sender_msg_key, peer_crypt_pkey)
    owner_timestamp = TimeKeeper.now_unix()

    key_struct =
      struct(DialogKey, %{
        dialog_hash: dialog_hash,
        sender_hash: user.user_hash,
        peer_hash: peer_hash,
        peer_kem_wrap_key_b64: kem_wrap_key,
        peer_wrapped_msg_key_b64: wrapped_msg_key,
        owner_timestamp: owner_timestamp,
        deleted_flag: false
      })

    sign_b64 = sign(key_struct, user.sign_skey)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "dialog_hash" => dialog_hash,
            "sender_hash" => user.user_hash,
            "peer_hash" => peer_hash,
            "peer_kem_wrap_key_b64" => encode_base64(kem_wrap_key),
            "peer_wrapped_msg_key_b64" => encode_base64(wrapped_msg_key),
            "owner_timestamp" => owner_timestamp,
            "deleted_flag" => false,
            "sign_b64" => encode_base64(sign_b64)
          },
          "syncMetadata" => %{"relation" => "dialog_keys"}
        }
      ]
    }

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{dialog_hash: dialog_hash, log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def publish_dialog_message(user, dialog_hash, plaintext, refs_tails, base_url) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(
        user.sign_skey,
        user.crypt_skey,
        user.contact_skey,
        refs_tails.peer_hash
      )

    message_id = DialogMessageId.generate()
    prepared = Content.prepare_for_send(plaintext)
    content_b64 = Crypto.encrypt_content(prepared, sender_msg_key)
    refs_map_b64 = Crypto.encrypt_refs_map(refs_tails.tails, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    msg_struct =
      struct(DialogMessage, %{
        message_id: message_id,
        dialog_hash: dialog_hash,
        sender_hash: user.user_hash,
        content_b64: content_b64,
        deleted_flag: false,
        refs_map_b64: refs_map_b64,
        parent_sign_hash: nil,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(msg_struct, user.sign_skey)
    sign_hash = Crypto.compute_sign_hash(sign_b64)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "message_id" => message_id,
            "dialog_hash" => dialog_hash,
            "sender_hash" => user.user_hash,
            "content_b64" => encode_base64(content_b64),
            "deleted_flag" => false,
            "refs_map_b64" => encode_base64(refs_map_b64),
            "parent_sign_hash" => nil,
            "owner_timestamp" => owner_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "dialog_messages"}
        }
      ]
    }

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} ->
        {:ok, %{message_id: message_id, sign_hash: sign_hash, log_entries: logs}}

      {:error, reason, logs} ->
        {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def publish_edit_message(
        user,
        dialog_hash,
        message_id,
        current_sign_hash,
        new_plaintext,
        refs_tails,
        base_url
      ) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(
        user.sign_skey,
        user.crypt_skey,
        user.contact_skey,
        refs_tails.peer_hash
      )

    prepared = Content.prepare_for_send(new_plaintext)
    content_b64 = Crypto.encrypt_content(prepared, sender_msg_key)
    refs_map_b64 = Crypto.encrypt_refs_map(refs_tails.tails, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    msg_struct =
      struct(DialogMessage, %{
        message_id: message_id,
        dialog_hash: dialog_hash,
        sender_hash: user.user_hash,
        content_b64: content_b64,
        deleted_flag: false,
        refs_map_b64: refs_map_b64,
        parent_sign_hash: current_sign_hash,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(msg_struct, user.sign_skey)
    sign_hash = Crypto.compute_sign_hash(sign_b64)

    payload =
      update_payload(
        "dialog_messages",
        %{
          "message_id" => message_id,
          "sender_hash" => user.user_hash,
          "dialog_hash" => dialog_hash
        },
        %{
          "content_b64" => encode_base64(content_b64),
          "deleted_flag" => false,
          "refs_map_b64" => encode_base64(refs_map_b64),
          "parent_sign_hash" => current_sign_hash,
          "owner_timestamp" => owner_timestamp,
          "sign_b64" => encode_base64(sign_b64),
          "sign_hash" => sign_hash
        }
      )

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{sign_hash: sign_hash, log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def publish_delete_message(
        user,
        dialog_hash,
        message_id,
        current_sign_hash,
        refs_tails,
        base_url
      ) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(
        user.sign_skey,
        user.crypt_skey,
        user.contact_skey,
        refs_tails.peer_hash
      )

    refs_map_b64 = Crypto.encrypt_refs_map(refs_tails.tails, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    msg_struct =
      struct(DialogMessage, %{
        message_id: message_id,
        dialog_hash: dialog_hash,
        sender_hash: user.user_hash,
        content_b64: "",
        deleted_flag: true,
        refs_map_b64: refs_map_b64,
        parent_sign_hash: current_sign_hash,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(msg_struct, user.sign_skey)
    sign_hash = Crypto.compute_sign_hash(sign_b64)

    payload =
      update_payload(
        "dialog_messages",
        %{
          "message_id" => message_id,
          "sender_hash" => user.user_hash,
          "dialog_hash" => dialog_hash
        },
        %{
          "content_b64" => "",
          "deleted_flag" => true,
          "refs_map_b64" => encode_base64(refs_map_b64),
          "parent_sign_hash" => current_sign_hash,
          "owner_timestamp" => owner_timestamp,
          "sign_b64" => encode_base64(sign_b64),
          "sign_hash" => sign_hash
        }
      )

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def start_message_stream(dialog_hash, base_url, subscriber_pid) do
    client = Electric.Client.new!(endpoint: base_url <> "/electric/v1/shapes")

    shape =
      Electric.Client.ShapeDefinition.new!("dialog_messages",
        where: "dialog_hash = '#{dialog_hash}'"
      )

    spawn(fn ->
      client
      |> Electric.Client.stream(shape, live: false, replica: :full, errors: :stream)
      |> Stream.transform(
        fn -> {[], nil} end,
        fn
          %Message.ChangeMessage{headers: %{operation: op}, value: value}, {msgs, resume}
          when op in [:insert, :update] ->
            {[], {[value | msgs], resume}}

          %Message.ResumeMessage{} = resume, {msgs, nil} ->
            {[], {msgs, resume}}

          _other, acc ->
            {[], acc}
        end,
        fn {msgs, resume} ->
          send(subscriber_pid, {:dialog_msgs_loaded, Enum.reverse(msgs)})

          stream_opts =
            if resume,
              do: [resume: resume, replica: :full, errors: :stream],
              else: [replica: :full, errors: :stream]

          client
          |> Electric.Client.stream(shape, stream_opts)
          |> Stream.each(fn
            %Message.ChangeMessage{headers: %{operation: :insert}, value: value} ->
              send(subscriber_pid, {:dialog_msg_new, value})

            %Message.ChangeMessage{headers: %{operation: :update}, value: value} ->
              send(subscriber_pid, {:dialog_msg_updated, value})

            %Message.ControlMessage{control: :up_to_date} ->
              send(subscriber_pid, {:dialog_msg_live})

            _ ->
              :ok
          end)
          |> Stream.run()
        end
      )
      |> Stream.run()
    end)
  end

  def publish_reaction(
        user,
        dialog_hash,
        message_id,
        message_sign_hash,
        emoji,
        peer_hash,
        base_url
      ) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)

    reaction_hash =
      Crypto.compute_reaction_hash(sender_msg_key, message_id, user.user_hash, emoji)

    type_b64 = Crypto.encrypt_emoji(emoji, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    reaction_struct =
      struct(DialogMessageReaction, %{
        reaction_hash: reaction_hash,
        dialog_hash: dialog_hash,
        message_id: message_id,
        message_sign_hash: message_sign_hash,
        reactor_hash: user.user_hash,
        type_b64: type_b64,
        deleted_flag: false,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(reaction_struct, user.sign_skey)

    fields = %{
      "reaction_hash" => reaction_hash,
      "dialog_hash" => dialog_hash,
      "message_id" => message_id,
      "message_sign_hash" => message_sign_hash,
      "reactor_hash" => user.user_hash,
      "type_b64" => encode_base64(type_b64),
      "deleted_flag" => false,
      "owner_timestamp" => owner_timestamp,
      "sign_b64" => encode_base64(sign_b64)
    }

    publish_insert("dialog_message_reactions", fields, user.sign_skey, base_url)
  end

  def delete_reaction(user, existing_reaction, peer_hash, base_url) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)

    type_b64 = Crypto.encrypt_emoji("", sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    reaction_struct =
      struct(DialogMessageReaction, %{
        reaction_hash: existing_reaction.reaction_hash,
        dialog_hash: existing_reaction.dialog_hash,
        message_id: existing_reaction.message_id,
        message_sign_hash: existing_reaction.message_sign_hash,
        reactor_hash: user.user_hash,
        type_b64: type_b64,
        deleted_flag: true,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(reaction_struct, user.sign_skey)

    payload =
      update_payload(
        "dialog_message_reactions",
        %{
          "reaction_hash" => existing_reaction.reaction_hash,
          "reactor_hash" => user.user_hash,
          "dialog_hash" => existing_reaction.dialog_hash,
          "message_id" => existing_reaction.message_id
        },
        %{
          "type_b64" => encode_base64(type_b64),
          "deleted_flag" => true,
          "owner_timestamp" => owner_timestamp,
          "sign_b64" => encode_base64(sign_b64)
        }
      )

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def publish_receipt(user, dialog_hash, message_id, message_sign_hash, type, base_url) do
    receipt_hash =
      Crypto.compute_receipt_hash(message_id, message_sign_hash, user.user_hash, type)

    owner_timestamp = TimeKeeper.now_unix()

    receipt_struct =
      struct(DialogMessageReceipt, %{
        receipt_hash: receipt_hash,
        dialog_hash: dialog_hash,
        message_id: message_id,
        peer_hash: user.user_hash,
        type: type,
        message_sign_hash: message_sign_hash,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(receipt_struct, user.sign_skey)

    fields = %{
      "receipt_hash" => receipt_hash,
      "dialog_hash" => dialog_hash,
      "message_id" => message_id,
      "peer_hash" => user.user_hash,
      "type" => type,
      "message_sign_hash" => message_sign_hash,
      "owner_timestamp" => owner_timestamp,
      "sign_b64" => encode_base64(sign_b64)
    }

    publish_insert("dialog_message_receipts", fields, user.sign_skey, base_url)
  end

  def fetch_reactions(dialog_hash, base_url) do
    base_url
    |> fetch_shape("dialog_message_reactions", "dialog_hash='#{dialog_hash}'")
    |> wrap_result(:reactions)
  end

  def fetch_receipts(dialog_hash, base_url) do
    base_url
    |> fetch_shape("dialog_message_receipts", "dialog_hash='#{dialog_hash}'")
    |> wrap_result(:receipts)
  end

  def start_reaction_stream(dialog_hash, base_url, subscriber_pid) do
    start_auxiliary_stream(
      "dialog_message_reactions",
      dialog_hash,
      base_url,
      subscriber_pid,
      :reactions_loaded,
      :reaction_change
    )
  end

  def start_receipt_stream(dialog_hash, base_url, subscriber_pid) do
    start_auxiliary_stream(
      "dialog_message_receipts",
      dialog_hash,
      base_url,
      subscriber_pid,
      :receipts_loaded,
      :receipt_change
    )
  end

  defp start_auxiliary_stream(
         table,
         dialog_hash,
         base_url,
         subscriber_pid,
         loaded_tag,
         change_tag
       ) do
    client = Electric.Client.new!(endpoint: base_url <> "/electric/v1/shapes")

    shape =
      Electric.Client.ShapeDefinition.new!(table,
        where: "dialog_hash = '#{dialog_hash}'"
      )

    spawn(fn ->
      client
      |> Electric.Client.stream(shape, live: false, replica: :full, errors: :stream)
      |> Stream.transform(
        fn -> {[], nil} end,
        fn
          %Message.ChangeMessage{headers: %{operation: op}, value: value}, {rows, resume}
          when op in [:insert, :update] ->
            {[], {[value | rows], resume}}

          %Message.ResumeMessage{} = resume, {rows, nil} ->
            {[], {rows, resume}}

          _other, acc ->
            {[], acc}
        end,
        fn {rows, resume} ->
          send(subscriber_pid, {loaded_tag, Enum.reverse(rows)})

          stream_opts =
            if resume,
              do: [resume: resume, replica: :full, errors: :stream],
              else: [replica: :full, errors: :stream]

          client
          |> Electric.Client.stream(shape, stream_opts)
          |> Stream.each(fn
            %Message.ChangeMessage{headers: %{operation: op}, value: value}
            when op in [:insert, :update] ->
              send(subscriber_pid, {change_tag, value})

            _ ->
              :ok
          end)
          |> Stream.run()
        end
      )
      |> Stream.run()
    end)
  end

  defp publish_insert(relation, fields, sign_skey, base_url) do
    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => fields,
          "syncMetadata" => %{"relation" => relation}
        }
      ]
    }

    case ingest(payload, sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  defp update_payload(relation, original, changes) do
    %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => original,
          "changes" => changes,
          "syncMetadata" => %{"relation" => relation}
        }
      ]
    }
  end

  defp wrap_result({:ok, rows, log}, key), do: {:ok, %{key => rows, log_entries: [log]}}

  defp wrap_result({:error, reason, log}, _key),
    do: {:error, %{reason: reason, log_entries: [log]}}

  defp sign(struct, sign_skey) do
    struct
    |> Integrity.signature_payload()
    |> EnigmaPq.sign(sign_skey)
  end
end
