defmodule ChatWeb.ElectricLive.DialogSandboxLive.ApiClient do
  @moduledoc """
  API client for dialog Electric ingest/shape operations with request logging.
  All reads go through Electric shape endpoints — no direct Ecto queries.
  """

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Types.DialogMessageId
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias Electric.Client.Message

  def fetch_all_user_cards(base_url) do
    url = "#{base_url}/electric/v1/shapes?table=user_cards&offset=-1"

    case fetch_shape(url) do
      {:ok, rows, log} -> {:ok, %{cards: rows, log_entries: [log]}}
      {:error, reason, log} -> {:error, %{reason: reason, log_entries: [log]}}
    end
  end

  def fetch_user_card(user_hash, base_url) do
    url = shapes_url(base_url, "user_cards", "user_hash='#{user_hash}'")

    case fetch_shape(url) do
      {:ok, rows, log} ->
        card = List.first(rows)
        {:ok, %{card: card, log_entries: [log]}}

      {:error, reason, log} ->
        {:error, %{reason: reason, log_entries: [log]}}
    end
  end

  def fetch_dialog_keys(user_hash, base_url) do
    # sender_hash requires ::text cast — Electric can't filter on 2nd PK column directly
    url_sender = shapes_url(base_url, "dialog_keys", "sender_hash::text='#{user_hash}'")
    url_peer = shapes_url(base_url, "dialog_keys", "peer_hash='#{user_hash}'")

    with {:ok, sender_rows, log1} <- fetch_shape(url_sender),
         {:ok, peer_rows, log2} <- fetch_shape(url_peer) do
      all_keys =
        (sender_rows ++ peer_rows)
        |> Enum.uniq_by(&{&1["dialog_hash"], &1["sender_hash"]})

      {:ok, %{keys: all_keys, log_entries: [log1, log2]}}
    else
      {:error, reason, log} -> {:error, %{reason: reason, log_entries: [log]}}
    end
  end

  def fetch_dialog_keys_by_dialog(dialog_hash, base_url) do
    url = shapes_url(base_url, "dialog_keys", "dialog_hash='#{dialog_hash}'")

    case fetch_shape(url) do
      {:ok, rows, log} -> {:ok, %{keys: rows, log_entries: [log]}}
      {:error, reason, log} -> {:error, %{reason: reason, log_entries: [log]}}
    end
  end

  def fetch_dialog_messages(dialog_hash, base_url) do
    url = shapes_url(base_url, "dialog_messages", "dialog_hash='#{dialog_hash}'")

    case fetch_shape(url) do
      {:ok, rows, log} -> {:ok, %{messages: rows, log_entries: [log]}}
      {:error, reason, log} -> {:error, %{reason: reason, log_entries: [log]}}
    end
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

    sign_b64 =
      key_struct
      |> Integrity.signature_payload()
      |> then(&EnigmaPq.sign(&1, user.sign_skey))

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

    with {:ok, challenge_resp, challenge_log} <- get_challenge(base_url),
         {:ok, _resp, ingest_log} <-
           post_ingest(challenge_resp, payload, user.sign_skey, base_url) do
      {:ok, %{dialog_hash: dialog_hash, log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} -> {:error, %{reason: reason, log_entries: log_entries}}
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
    content_b64 = Crypto.encrypt_content(plaintext, sender_msg_key)
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

    sign_b64 =
      msg_struct
      |> Integrity.signature_payload()
      |> then(&EnigmaPq.sign(&1, user.sign_skey))

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

    with {:ok, challenge_resp, challenge_log} <- get_challenge(base_url),
         {:ok, _resp, ingest_log} <-
           post_ingest(challenge_resp, payload, user.sign_skey, base_url) do
      {:ok,
       %{message_id: message_id, sign_hash: sign_hash, log_entries: [challenge_log, ingest_log]}}
    else
      {:error, reason, log_entries} -> {:error, %{reason: reason, log_entries: log_entries}}
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
          %Message.ChangeMessage{headers: %{operation: :insert}, value: value}, {msgs, resume} ->
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

  # --- Private helpers ---

  defp shapes_url(base_url, table, where) do
    "#{base_url}/electric/v1/shapes?table=#{table}&offset=-1&where=#{URI.encode(where)}"
  end

  defp fetch_shape(url) do
    timestamp = TimeKeeper.now()
    headers = [{"accept", "application/json"}]

    case fetch_shape_pages(url, headers, []) do
      {:ok, rows} ->
        {:ok, rows,
         build_log("GET", url, headers, "", 200, [], Jason.encode!(rows, pretty: true), timestamp)}

      {:error, {status, body, rh}} ->
        {:error, "Shape request failed (#{status})",
         build_log("GET", url, headers, "", status, rh, inspect(body), timestamp)}

      {:error, reason} ->
        {:error, "Shape request failed: #{inspect(reason)}",
         build_log("GET", url, headers, "", 0, [], inspect(reason), timestamp)}
    end
  end

  defp fetch_shape_pages(url, headers, acc) do
    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body, headers: rh}} ->
        rows = acc ++ parse_shape_response(body)

        if up_to_date?(body) do
          {:ok, rows}
        else
          next_url = next_page_url(url, rh)
          fetch_shape_pages(next_url, headers, rows)
        end

      {:ok, %{status: 204}} ->
        {:ok, acc}

      {:ok, %{status: s, body: b, headers: rh}} ->
        {:error, {s, b, rh}}

      {:error, e} ->
        {:error, e}
    end
  end

  defp up_to_date?(body) when is_list(body) do
    Enum.any?(body, &match?(%{"headers" => %{"control" => "up-to-date"}}, &1))
  end

  defp up_to_date?(_), do: true

  defp next_page_url(url, resp_headers) do
    offset = resp_headers["electric-offset"] |> List.first()
    handle = resp_headers["electric-handle"] |> List.first()

    url
    |> URI.parse()
    |> then(fn uri ->
      params =
        URI.decode_query(uri.query)
        |> Map.put("offset", offset)
        |> Map.put("handle", handle)

      %{uri | query: URI.encode_query(params)}
    end)
    |> URI.to_string()
  end

  defp parse_shape_response(body) when is_list(body) do
    body
    |> Enum.filter(&match?(%{"headers" => %{"operation" => "insert"}, "value" => _}, &1))
    |> Enum.map(& &1["value"])
  end

  defp parse_shape_response(_), do: []

  defp get_challenge(base_url) do
    url = base_url <> "/electric/v1/challenge"
    timestamp = TimeKeeper.now()
    headers = [{"accept", "application/json"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body, headers: rh}} ->
        {:ok, body,
         build_log("GET", url, headers, "", 200, rh, Jason.encode!(body, pretty: true), timestamp)}

      {:ok, %{status: s, body: b, headers: rh}} ->
        {:error, "Challenge failed (#{s})",
         [build_log("GET", url, headers, "", s, rh, inspect(b), timestamp)]}

      {:error, e} ->
        {:error, "Challenge failed: #{inspect(e)}",
         [build_log("GET", url, headers, "", 0, [], inspect(e), timestamp)]}
    end
  end

  defp post_ingest(challenge_resp, payload, sign_skey, base_url) do
    %{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp
    signature = EnigmaPq.sign(challenge, sign_skey)
    signature_b64 = Base.encode64(signature, padding: false)

    payload_with_auth =
      Map.put(payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

    url = base_url <> "/electric/v1/ingest"
    timestamp = TimeKeeper.now()
    headers = [{"accept", "application/json"}, {"content-type", "application/json"}]
    req_body = Jason.encode!(payload_with_auth, pretty: true)

    case Req.post(url, json: payload_with_auth, headers: headers) do
      {:ok, %{status: s, body: b, headers: rh}} when s in 200..299 ->
        {:ok, b,
         build_log(
           "POST",
           url,
           headers,
           req_body,
           s,
           rh,
           Jason.encode!(b, pretty: true),
           timestamp
         )}

      {:ok, %{status: s, body: b, headers: rh}} ->
        {:error, "Ingest failed (#{s})",
         [build_log("POST", url, headers, req_body, s, rh, inspect(b), timestamp)]}

      {:error, e} ->
        {:error, "Ingest failed: #{inspect(e)}",
         [build_log("POST", url, headers, req_body, 0, [], inspect(e), timestamp)]}
    end
  end

  defp build_log(method, url, req_headers, req_body, status, resp_headers, resp_body, timestamp) do
    %{
      timestamp: timestamp,
      method: method,
      url: url,
      request_headers: req_headers,
      request_body: req_body,
      response_status: status,
      response_headers: resp_headers,
      response_body: resp_body
    }
  end

  defp encode_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)
end
