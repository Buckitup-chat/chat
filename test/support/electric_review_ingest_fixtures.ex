defmodule Chat.Test.ElectricReviewIngestFixtures do
  @moduledoc """
  Review ingest setups shared by the `electric_controller_review_*` tests: the author / owner /
  origin parties behind an origin with a given moderation mode, and a signed `review` insert
  mutation as the client would send it to `POST /electric/v1/ingest`.
  """

  import Chat.Test.ElectricIngestHelpers, only: [signature_and_hash: 3, to_base64: 1]
  import Chat.Test.ReviewFixtures, only: [insert_origin: 3, insert_user_card: 1]

  alias Chat.Data.Schemas.Review
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User, as: UserData

  @doc """
  Inserts signed user cards for an author, an owner and an origin identity, inserts the origin
  with `moderation_mode` and returns `conn`, `author`, `author_hash`, `origin_identity` and
  `origin_hash`.
  """
  def review_ingest_parties(conn, moderation_mode) do
    author = UserData.generate_pq_identity("Author")
    owner = UserData.generate_pq_identity("Owner")
    origin_identity = UserData.generate_pq_identity("CoffeeShop")

    author_card = insert_user_card(author)
    _owner_card = insert_user_card(owner)
    _origin_card = insert_user_card(origin_identity)

    insert_origin(origin_identity, owner, moderation_mode)
    origin_hash = UserData.extract_pq_card(origin_identity).user_hash

    %{
      conn: conn,
      author: author,
      author_hash: author_card.user_hash,
      origin_identity: origin_identity,
      origin_hash: origin_hash
    }
  end

  @doc """
  A fresh review by `ctx.author` on `ctx.origin_hash`, signed by the author, as an ingest
  `insert` mutation. Returns `{review_hash, mutation, sign_hash}`.
  """
  def build_review_mutation(ctx) do
    review_hash = :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    ts = System.os_time(:millisecond)

    review = %Review{
      review_hash: review_hash,
      origin_hash: ctx.origin_hash,
      author_hash: ctx.author_hash,
      content_b64: :crypto.strong_rand_bytes(48),
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: ts
    }

    {sign_b64, sign_hash} =
      signature_and_hash(review, ctx.author.sign_skey, &ReviewSignHash.from_binary/1)

    mutation = %{
      "type" => "insert",
      "modified" => %{
        "review_hash" => review_hash,
        "origin_hash" => ctx.origin_hash,
        "author_hash" => ctx.author_hash,
        "content_b64" => to_base64(review.content_b64),
        "deleted_flag" => false,
        "owner_timestamp" => ts,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review"}
    }

    {review_hash, mutation, sign_hash}
  end
end
