defmodule Chat.Test.ReviewCandidateIngestFixtures do
  @moduledoc """
  Ingest-triggered review promotion setups shared by the `electric_controller_candidate_ingest_*`
  tests: the author / owner / origin parties, a review on an origin with a given moderation
  mode, signed password / null candidate inserts and right-candidate signature updates as the
  client would send them to `POST /electric/v1/ingest`.
  """

  import Chat.Test.ElectricIngestHelpers, only: [post_ingest: 3, to_base64: 1]
  import Chat.Test.ReviewFixtures, only: [insert_origin: 3, insert_review: 2, insert_user_card: 1]

  alias Chat.Data.Integrity
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias Chat.Data.User, as: UserData

  @doc """
  Setup: inserts signed user cards for an author, an owner and an origin identity and returns
  them with `author_hash` and `origin_hash`.
  """
  def candidate_ingest_parties(%{conn: conn}) do
    author = UserData.generate_pq_identity("Author")
    owner = UserData.generate_pq_identity("Owner")
    origin_identity = UserData.generate_pq_identity("CoffeeShop")

    author_card = insert_user_card(author)
    _owner_card = insert_user_card(owner)
    _origin_card = insert_user_card(origin_identity)

    %{
      conn: conn,
      author: author,
      author_hash: author_card.user_hash,
      owner: owner,
      origin_identity: origin_identity,
      origin_hash: UserData.extract_pq_card(origin_identity).user_hash
    }
  end

  @doc "Setup: inserts the origin with `moderation_mode` and a review by the author on it."
  def origin_with_review(ctx, moderation_mode) do
    insert_origin(ctx.origin_identity, ctx.owner, moderation_mode)
    review = insert_review(ctx.author, ctx.origin_hash)
    {:ok, review: review}
  end

  @doc """
  Phase 1 via ingest: posts the password and null candidates for `ctx.review` (crashing unless
  both are accepted) and returns `{revoke_candidate, post_candidate}`; the post candidate is
  `nil` unless `mode` is `:pre`.
  """
  def phase1_via_ingest!(ctx, mode) do
    pwd_mutation = build_candidate_mutation(ctx, ctx.review, :password)
    null_mutation = build_candidate_mutation(ctx, ctx.review, :null)

    %{status: 200} = post_ingest(ctx.conn, %{"mutations" => [pwd_mutation]}, ctx.author.sign_skey)

    %{status: 200} =
      post_ingest(ctx.conn, %{"mutations" => [null_mutation]}, ctx.author.sign_skey)

    revoke = RightCandidateData.get_revoke_candidate(ctx.review.review_hash)

    post =
      if mode == :pre,
        do: RightCandidateData.get_post_candidate(ctx.review.review_hash),
        else: nil

    {revoke, post}
  end

  @doc "A `:password` or `:null` candidate insert by `ctx.author` for `review`."
  def build_candidate_mutation(ctx, review, type, opts \\ []) do
    build_candidate_mutation_for(ctx.author, ctx.author_hash, review, ctx.origin_hash, type, opts)
  end

  @doc """
  A `:password` or `:null` candidate insert signed by `author` and claiming `author_hash`.
  `opts[:timestamp]` overrides the owner timestamp (null defaults to one past the password's).
  """
  def build_candidate_mutation_for(author, author_hash, review, origin_hash, type, opts \\ []) do
    password_b64 = if type == :password, do: review.review_password
    base_ts = review.owner_timestamp + 100_000
    default_ts = if type == :null, do: base_ts + 1, else: base_ts
    ts = Keyword.get(opts, :timestamp, default_ts)

    signable = %ReviewPublicPassword{
      review_hash: review.review_hash,
      sign_hash: nil,
      origin_hash: origin_hash,
      password_b64: password_b64,
      author_hash: author_hash,
      deleted_flag: false,
      owner_timestamp: ts
    }

    sign_b64 = signable |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()

    modified =
      %{
        "review_hash" => review.review_hash,
        "sign_hash" => sign_hash,
        "origin_hash" => origin_hash,
        "author_hash" => author_hash,
        "owner_timestamp" => ts,
        "sign_b64" => to_base64(sign_b64)
      }
      |> maybe_put("password_b64", password_b64)

    %{
      "type" => "insert",
      "modified" => modified,
      "syncMetadata" => %{"relation" => "review_password_candidate"}
    }
  end

  @doc "An update signing a `:post` or `:revoke` right `candidate` with `signer`'s key."
  def build_right_sign_mutation(candidate, signer, type) do
    sign_b64 = candidate |> Integrity.signature_payload() |> EnigmaPq.sign(signer.sign_skey)

    sign_hash =
      case type do
        :post -> sign_b64 |> EnigmaPq.hash() |> ReviewPostRightSignHash.from_binary()
        :revoke -> sign_b64 |> EnigmaPq.hash() |> ReviewRevokeRightSignHash.from_binary()
      end

    relation =
      case type do
        :post -> "review_post_right_candidate"
        :revoke -> "review_revoke_right_candidate"
      end

    %{
      "type" => "update",
      "original" => %{"review_hash" => candidate.review_hash},
      "changes" => %{
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => relation}
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, to_base64(value))
end
