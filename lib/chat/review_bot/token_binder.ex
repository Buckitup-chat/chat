defmodule Chat.ReviewBot.TokenBinder do
  @moduledoc "Binds a reviewer identity to a review write token. Issues per-shape vouches."

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.DeviceId
  alias Chat.ReviewBot.BinderQueries
  alias Chat.ReviewBot.RowBuilder
  alias Chat.ReviewBot.TokenCreator
  alias Chat.ReviewBot.Worker
  alias Chat.TimeKeeper

  @review_shapes ~w(review review_password_candidate review_post_right_candidate review_revoke_right_candidate)

  @doc """
  Binds `reviewer_hash` to the token behind `nonce`, returns `{:ok, bound_nonce}`.

  Bound copies are not invitations. An order-linked token binds once (same user
  gets it back), a reusable root yields one copy per user. Runs under a per-nonce
  lock so a single device never double-binds.
  """
  def bind(nonce, reviewer_hash, pop_context) do
    nonce
    |> ReviewWriteTokenNonceHash.from_nonce()
    |> then(&{__MODULE__, &1})
    |> then(
      &:global.trans({&1, self()}, fn -> locked_bind(nonce, reviewer_hash, pop_context) end)
    )
  end

  defp locked_bind(nonce, reviewer_hash, pop_context) do
    with {:ok, token} <- fetch_valid_token(nonce),
         {:invitation, true} <- {:invitation, is_nil(token.parent_nonce_hash)},
         {:ok, _card} <- verify_reviewer(reviewer_hash, pop_context),
         bot_hash = token.review_bot_hash,
         {:ok, %{origin_hash: origin_hash}} <- fetch_bot_info(bot_hash),
         :ok <- verify_bot_origin_vouch(origin_hash, bot_hash),
         :ok <- verify_bot_device_vouches(bot_hash) do
      do_bind(token, nonce, origin_hash, reviewer_hash)
    else
      {:invitation, false} -> {:error, :token_not_invitation}
      error -> error
    end
  end

  defp fetch_valid_token(nonce) do
    case nonce
         |> ReviewWriteTokenNonceHash.from_nonce()
         |> BinderQueries.get_review_write_token() do
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

  defp do_bind(token, nonce, origin_hash, reviewer_hash) do
    bot_hash = token.review_bot_hash

    case {token.origin_order_hash, token.user_hash} do
      {nil, _} -> bind_reusable(token, bot_hash, origin_hash, reviewer_hash)
      {_order, nil} -> bind_order_linked(token, bot_hash, origin_hash, reviewer_hash, nonce)
      {_order, ^reviewer_hash} -> {:ok, nonce}
      {_order, _other} -> {:error, :token_already_bound}
    end
  end

  defp bind_order_linked(%ReviewWriteToken{} = token, bot_hash, origin_hash, reviewer_hash, nonce) do
    bound = %ReviewWriteToken{
      token
      | user_hash: reviewer_hash,
        # the Writer refuses updates not strictly newer; bind may land in the create second
        owner_timestamp: max(TimeKeeper.now_unix(), token.owner_timestamp + 1)
    }

    bot_hash
    |> build_vouch_mutations(origin_hash, reviewer_hash, token.nonce_hash)
    |> Enum.concat([RowBuilder.review_write_token_update_mutation(bound, [:user_hash])])
    |> ingest(bot_hash, nonce)
  end

  defp bind_reusable(token, bot_hash, origin_hash, reviewer_hash) do
    case BinderQueries.get_bound_copy(token.nonce_hash, reviewer_hash) do
      nil -> mint_copy(token, bot_hash, origin_hash, reviewer_hash)
      copy -> Worker.unwrap_nonce(bot_hash, copy.nonce_enc_b64)
    end
  end

  defp mint_copy(token, bot_hash, origin_hash, reviewer_hash) do
    new_nonce = TokenCreator.generate_nonce()
    new_nonce_hash = ReviewWriteTokenNonceHash.from_nonce(new_nonce)

    bound = %ReviewWriteToken{
      nonce_hash: new_nonce_hash,
      nonce_enc_b64: Worker.wrap_nonce(bot_hash, new_nonce),
      origin_hash: origin_hash,
      review_bot_hash: bot_hash,
      origin_order_hash: nil,
      parent_nonce_hash: token.nonce_hash,
      user_hash: reviewer_hash,
      review_hash: nil,
      deleted_flag: false,
      owner_timestamp: TimeKeeper.now_unix()
    }

    bot_hash
    |> build_vouch_mutations(origin_hash, reviewer_hash, new_nonce_hash)
    |> Enum.concat([RowBuilder.review_write_token_mutation(bound)])
    |> ingest(bot_hash, new_nonce)
  end

  defp ingest(mutations, bot_hash, bound_nonce) do
    case Worker.ingest(bot_hash, mutations) do
      {:ok, _txid, _changes} -> {:ok, bound_nonce}
      error -> error
    end
  end

  defp build_vouch_mutations(bot_hash, origin_hash, reviewer_hash, nonce_hash) do
    origin_vouch =
      build_vouch(bot_hash, reviewer_hash, "origins.#{origin_hash}.reviews.write.#{nonce_hash}")

    device_id = DeviceId.id()

    device_vouches =
      Enum.map(@review_shapes, fn shape ->
        build_vouch(bot_hash, reviewer_hash, "device.#{device_id}.storage.write.#{shape}")
      end)

    [origin_vouch | device_vouches]
    |> Enum.reject(&live_vouch?/1)
  end

  # Device vouches are shared by every token the reviewer binds via this bot
  defp live_vouch?(%{
         "modified" => %{"kind" => kind, "issuer_hash" => issuer, "subject_hash" => subject}
       }) do
    match?(%{deleted_flag: false}, BinderQueries.get_vouch_token(kind, issuer, subject))
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
end
