defmodule Chat.Data.Review.OriginGate do
  @moduledoc """
  Origin gate for review inserts (check phase).

  - `invite_only`: the author needs a **direct** vouch (any kind under
    `origins.<oh>.reviews.write.` except token vouches `….rwn_…`) or a nonce.
    An author whose only access is a token vouch gets `"nonce required"`.
  - Whenever `auth.nonce` is present (any mode) the token it names must be bound
    to the author, unused, live, of this origin, and the **exact** bind vouch
    `origins.<oh>.reviews.write.<nonce_hash>` (issuer = token bot) must be live.
  """

  alias Chat.Data.OriginSetting
  alias Chat.Data.ReviewWriteToken, as: TokenData
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.Consts
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.Pq.WriteGate
  alias Phoenix.Sync.Writer.Operation

  def check(%Operation{operation: :insert, changes: changes}, pop_context) do
    origin_hash = changes["origin_hash"] || changes[:origin_hash]
    author_hash = changes["author_hash"] || changes[:author_hash]
    nonce = nonce_from(pop_context)
    access = OriginSetting.get_review_access(origin_hash)

    with :ok <- check_access(access, origin_hash, author_hash, nonce) do
      check_token(nonce, access, author_hash, origin_hash)
    end
  end

  def check(%Operation{operation: :update}, _pop_context), do: :ok

  defp nonce_from(%{nonce: nonce}) when is_binary(nonce), do: nonce
  defp nonce_from(_pop_context), do: nil

  defp check_access(access, origin_hash, author_hash, nonce) do
    cond do
      access == "open" -> :ok
      access != "invite_only" -> {:error, "not invited"}
      author_hash == origin_hash -> :ok
      is_binary(nonce) -> :ok
      true -> check_invited(origin_hash, author_hash)
    end
  end

  defp check_invited(origin_hash, author_hash) do
    scope = write_scope(origin_hash)
    token_kind_prefix = "#{scope}.#{token_child_prefix()}"

    {token_kinds, direct_kinds} =
      author_hash
      |> VouchTokenData.scoped_vouch_kinds(scope)
      |> Enum.split_with(&String.starts_with?(&1, token_kind_prefix))

    cond do
      direct_vouch?(origin_hash, author_hash, direct_kinds) -> :ok
      token_kinds != [] -> {:error, "nonce required"}
      true -> {:error, "not invited"}
    end
  end

  defp check_token(nil, _access, _author_hash, _origin_hash), do: :ok

  defp check_token(nonce, access, author_hash, origin_hash) do
    nonce_hash = ReviewWriteTokenNonceHash.from_nonce(nonce)
    kind = "#{write_scope(origin_hash)}.#{nonce_hash}"

    with {:ok, token} <-
           nonce_hash
           |> TokenData.get_review_write_token()
           |> check_token_row(author_hash, origin_hash),
         :ok <- check_bind_vouch(kind, token.review_bot_hash, author_hash) do
      check_bind_chain(access, origin_hash, author_hash, kind)
    end
  end

  defp check_token_row(token, author_hash, origin_hash) do
    case token do
      %ReviewWriteToken{
        deleted_flag: false,
        user_hash: ^author_hash,
        origin_hash: ^origin_hash,
        review_hash: nil
      } = token ->
        {:ok, token}

      %ReviewWriteToken{review_hash: rh} when not is_nil(rh) ->
        {:error, "token already used"}

      %ReviewWriteToken{deleted_flag: true} ->
        {:error, "token expired"}

      nil ->
        {:error, "token not found"}

      _ ->
        {:error, "token mismatch"}
    end
  end

  defp check_bind_vouch(kind, bot_hash, author_hash) do
    case VouchTokenData.get_vouch_token(kind, bot_hash, author_hash) do
      %VouchToken{deleted_flag: false} -> :ok
      _ -> {:error, "no bind vouch"}
    end
  end

  defp check_bind_chain("invite_only", origin_hash, author_hash, kind) do
    case VouchTokenData.chain_distance(origin_hash, author_hash, kind, WriteGate.max_depth()) do
      {:ok, _} -> :ok
      _ -> {:error, "not invited"}
    end
  end

  defp check_bind_chain(_access, _origin_hash, _author_hash, _kind), do: :ok

  defp direct_vouch?(origin_hash, author_hash, kinds) do
    Enum.any?(kinds, fn kind ->
      match?(
        {:ok, _},
        VouchTokenData.chain_distance(origin_hash, author_hash, kind, WriteGate.max_depth())
      )
    end)
  end

  defp write_scope(origin_hash), do: "origins.#{origin_hash}.reviews.write"

  defp token_child_prefix, do: Consts.review_write_token_nonce_prefix()
end
