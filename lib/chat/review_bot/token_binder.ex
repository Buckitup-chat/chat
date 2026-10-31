defmodule Chat.ReviewBot.TokenBinder do
  @moduledoc "Binds a reviewer identity to a review write token. Issues per-shape vouches."

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewWriteTokenSignHash
  alias Chat.DeviceId
  alias Chat.ReviewBot.BinderQueries
  alias Chat.ReviewBot.Worker
  alias Chat.TimeKeeper

  @review_shapes ~w(review review_password_candidate review_post_right_candidate review_revoke_right_candidate)
  @nonce_bytes 24

  def bind(nonce, reviewer_hash, pop_context) do
    with {:ok, token} <- fetch_valid_token(nonce),
         {:ok, _card} <- verify_reviewer(reviewer_hash, pop_context),
         bot_hash = token.review_bot_hash,
         {:ok, %{origin_hash: origin_hash}} <- fetch_bot_info(bot_hash),
         :ok <- verify_bot_origin_vouch(origin_hash, bot_hash),
         :ok <- verify_bot_device_vouches(bot_hash) do
      do_bind(token, bot_hash, origin_hash, reviewer_hash)
    end
  end

  defp fetch_valid_token(nonce) do
    case BinderQueries.get_review_write_token(nonce) do
      nil -> {:error, :token_not_found}
      %{deleted_flag: true} -> {:error, :token_deleted}
      %ReviewWriteToken{} = token -> {:ok, token}
    end
  end

  defp verify_reviewer(reviewer_hash, %{challenge: challenge, signature: signature}) do
    with {:card, card} when card != nil <- {:card, BinderQueries.get_card(reviewer_hash)},
         true <- BinderQueries.valid_card?(card),
         true <- EnigmaPq.verify(challenge, signature, card.sign_pkey) do
      {:ok, card}
    else
      {:card, nil} -> {:error, :reviewer_not_found}
      _ -> {:error, :invalid_pop}
    end
  end

  defp fetch_bot_info(bot_hash) do
    case Worker.running?(bot_hash) do
      true -> {:ok, Worker.info(bot_hash)}
      false -> {:error, :bot_not_running}
    end
  end

  defp verify_bot_origin_vouch(origin_hash, bot_hash) do
    kind = "origins.#{origin_hash}.reviews.write"

    case BinderQueries.get_vouch_token(kind, origin_hash, bot_hash) do
      %{deleted_flag: false} -> :ok
      _ -> {:error, :no_bot_origin_vouch}
    end
  end

  defp verify_bot_device_vouches(bot_hash) do
    device_id = DeviceId.id()
    prefix = "device.#{device_id}.storage.write"

    case BinderQueries.scoped_vouch_exists?(bot_hash, prefix) do
      true -> :ok
      false -> {:error, :no_bot_device_vouch}
    end
  end

  defp do_bind(token, bot_hash, origin_hash, reviewer_hash) do
    case token.origin_order_hash do
      nil -> bind_reusable(token, bot_hash, origin_hash, reviewer_hash)
      _order_hash -> bind_order_linked(token, bot_hash, origin_hash, reviewer_hash)
    end
  end

  defp bind_order_linked(%ReviewWriteToken{} = token, bot_hash, origin_hash, reviewer_hash) do
    bound = %ReviewWriteToken{
      token
      | user_hash: reviewer_hash,
        owner_timestamp: TimeKeeper.now_unix()
    }

    vouch_mutations = build_vouch_mutations(bot_hash, origin_hash, reviewer_hash, token.nonce)
    token_mutation = sign_and_build_token_mutation(bot_hash, bound)

    Worker.ingest(bot_hash, vouch_mutations ++ [token_mutation])
    |> then(fn
      {:ok, _txid, _changes} -> {:ok, token.nonce}
      error -> error
    end)
  end

  defp bind_reusable(token, bot_hash, origin_hash, reviewer_hash) do
    new_nonce = generate_nonce()

    bound = %ReviewWriteToken{
      nonce: new_nonce,
      origin_hash: origin_hash,
      review_bot_hash: bot_hash,
      origin_order_hash: nil,
      parent_nonce: token.nonce,
      user_hash: reviewer_hash,
      review_hash: nil,
      deleted_flag: false,
      owner_timestamp: TimeKeeper.now_unix()
    }

    vouch_mutations = build_vouch_mutations(bot_hash, origin_hash, reviewer_hash, new_nonce)
    token_mutation = sign_and_build_token_mutation(bot_hash, bound)

    Worker.ingest(bot_hash, vouch_mutations ++ [token_mutation])
    |> then(fn
      {:ok, _txid, _changes} -> {:ok, new_nonce}
      error -> error
    end)
  end

  defp sign_and_build_token_mutation(bot_hash, token) do
    payload = Integrity.signature_payload(token)
    sign_b64 = Worker.sign(bot_hash, payload)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewWriteTokenSignHash.from_binary()
    signed = %{token | sign_b64: sign_b64, sign_hash: sign_hash}

    %{
      "type" => "insert",
      "modified" => %{
        "nonce" => signed.nonce,
        "origin_hash" => signed.origin_hash,
        "review_bot_hash" => signed.review_bot_hash,
        "origin_order_hash" => signed.origin_order_hash,
        "parent_nonce" => signed.parent_nonce,
        "user_hash" => signed.user_hash,
        "review_hash" => signed.review_hash,
        "deleted_flag" => signed.deleted_flag,
        "owner_timestamp" => signed.owner_timestamp,
        "sign_b64" => signed.sign_b64,
        "sign_hash" => signed.sign_hash
      },
      "syncMetadata" => %{"relation" => "review_write_tokens"}
    }
  end

  defp build_vouch_mutations(bot_hash, origin_hash, reviewer_hash, nonce) do
    origin_vouch =
      build_vouch(bot_hash, reviewer_hash, "origins.#{origin_hash}.reviews.write.#{nonce}")

    device_id = DeviceId.id()

    device_vouches =
      Enum.map(@review_shapes, fn shape ->
        build_vouch(bot_hash, reviewer_hash, "device.#{device_id}.storage.write.#{shape}")
      end)

    [origin_vouch | device_vouches]
  end

  defp build_vouch(bot_hash, reviewer_hash, kind) do
    vouch = %VouchToken{
      kind: kind,
      issuer_hash: bot_hash,
      subject_hash: reviewer_hash,
      owner_timestamp: TimeKeeper.now_unix(),
      deleted_flag: false
    }

    payload = Integrity.signature_payload(vouch)
    sign_b64 = Worker.sign(bot_hash, payload)

    %{
      "type" => "insert",
      "modified" => %{
        "kind" => vouch.kind,
        "issuer_hash" => vouch.issuer_hash,
        "subject_hash" => vouch.subject_hash,
        "owner_timestamp" => vouch.owner_timestamp,
        "deleted_flag" => vouch.deleted_flag,
        "sign_b64" => sign_b64
      },
      "syncMetadata" => %{"relation" => "vouch_tokens"}
    }
  end

  defp generate_nonce do
    @nonce_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
