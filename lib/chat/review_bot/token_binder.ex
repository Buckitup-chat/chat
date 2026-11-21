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
  gets it back), a reusable root yields one copy per user.

  Stateless checks (token exists, is an invitation, reviewer PoP) run in the
  caller. The read-decide-write part runs inside the token's bot `Worker`
  (`bind_in_bot/4`), whose mailbox serializes binds, so a device never double-binds.
  """
  def bind(nonce, reviewer_hash, pop_context) do
    with {:ok, token} <- fetch_valid_token(nonce),
         {:invitation, true} <- {:invitation, is_nil(token.parent_nonce_hash)},
         {:ok, _card} <- verify_reviewer(reviewer_hash, pop_context),
         {:running, true} <- {:running, Worker.running?(token.review_bot_hash)} do
      Worker.bind(token.review_bot_hash, nonce, reviewer_hash)
    else
      {:invitation, false} -> {:error, :token_not_invitation}
      {:running, false} -> {:error, :bot_not_running}
      error -> error
    end
  end

  @doc """
  Runs inside the bot `Worker` process. `bot` carries the bot's hashes and its
  signing / nonce / ingest functions, so no secret key leaves the Worker.
  The token is re-read here: earlier reads may be stale.
  """
  def bind_in_bot(bot, nonce, reviewer_hash) do
    with {:ok, token} <- fetch_valid_token(nonce),
         :ok <- verify_bot_origin_vouch(bot.origin_hash, bot.bot_hash),
         :ok <- verify_bot_device_vouches(bot.bot_hash) do
      do_bind(token, bot, nonce, reviewer_hash)
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

  defp do_bind(token, bot, nonce, reviewer_hash) do
    case {token.origin_order_hash, token.user_hash} do
      {nil, _} -> bind_reusable(token, bot, reviewer_hash)
      {_order, nil} -> bind_order_linked(token, bot, nonce, reviewer_hash)
      {_order, ^reviewer_hash} -> {:ok, nonce}
      {_order, _other} -> {:error, :token_already_bound}
    end
  end

  defp bind_order_linked(%ReviewWriteToken{} = token, bot, nonce, reviewer_hash) do
    bound = %ReviewWriteToken{
      token
      | user_hash: reviewer_hash,
        # the Writer refuses updates not strictly newer; bind may land in the create second
        owner_timestamp: max(TimeKeeper.now_unix(), token.owner_timestamp + 1)
    }

    bot
    |> build_vouch_mutations(reviewer_hash, token.nonce_hash)
    |> Enum.concat([RowBuilder.review_write_token_update_mutation(bound, [:user_hash], bot.sign)])
    |> ingest(bot, nonce)
  end

  defp bind_reusable(token, bot, reviewer_hash) do
    case BinderQueries.get_bound_copy(token.nonce_hash, reviewer_hash) do
      nil -> mint_copy(token, bot, reviewer_hash)
      copy -> bot.unwrap_nonce.(copy.nonce_enc_b64)
    end
  end

  defp mint_copy(token, bot, reviewer_hash) do
    new_nonce = TokenCreator.generate_nonce()
    new_nonce_hash = ReviewWriteTokenNonceHash.from_nonce(new_nonce)

    bound = %ReviewWriteToken{
      nonce_hash: new_nonce_hash,
      nonce_enc_b64: bot.wrap_nonce.(new_nonce),
      origin_hash: bot.origin_hash,
      review_bot_hash: bot.bot_hash,
      origin_order_hash: nil,
      parent_nonce_hash: token.nonce_hash,
      user_hash: reviewer_hash,
      review_hash: nil,
      deleted_flag: false,
      owner_timestamp: TimeKeeper.now_unix()
    }

    bot
    |> build_vouch_mutations(reviewer_hash, new_nonce_hash)
    |> Enum.concat([RowBuilder.review_write_token_mutation(bound, bot.sign)])
    |> ingest(bot, new_nonce)
  end

  defp ingest(mutations, bot, bound_nonce) do
    case bot.ingest.(mutations) do
      {:ok, _txid, _changes} -> {:ok, bound_nonce}
      error -> error
    end
  end

  defp build_vouch_mutations(bot, reviewer_hash, nonce_hash) do
    origin_vouch =
      build_vouch(bot, reviewer_hash, "origins.#{bot.origin_hash}.reviews.write.#{nonce_hash}")

    device_id = DeviceId.id()

    device_vouches =
      Enum.map(@review_shapes, fn shape ->
        build_vouch(bot, reviewer_hash, "device.#{device_id}.storage.write.#{shape}")
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

  defp build_vouch(bot, reviewer_hash, kind) do
    vouch = %VouchToken{
      kind: kind,
      issuer_hash: bot.bot_hash,
      subject_hash: reviewer_hash,
      owner_timestamp: TimeKeeper.now_unix(),
      deleted_flag: false
    }

    sign_b64 = vouch |> Integrity.signature_payload() |> bot.sign.()

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
