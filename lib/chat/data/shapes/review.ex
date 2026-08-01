defmodule Chat.Data.Shapes.Review do
  @moduledoc "Shape behaviour implementation for review."

  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.Review.Validation
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Types.ReviewSignHash
  alias EnigmaPq
  alias Phoenix.Sync.Writer

  use Chat.Data.Shapes.Shape,
    persist: [
      upsert: &ReviewData.upsert_review/1,
      get: &ReviewData.get_review/1,
      lookup_key: :review_hash,
      validate_insert: &Validation.validate_review_insert/1,
      validate_update: &Validation.validate_review_update/2
    ]

  use Toolbox.OriginLog

  @impl true
  def shape_name, do: :review

  @impl true
  def schema_module, do: Review

  @impl true
  def sync_required_parents(_op, %{author_hash: ah}) do
    [{:user_card, ah}]
  end

  @impl true
  def sync_derive_fields(%Review{sign_b64: sign_b64} = review) when is_binary(sign_b64) do
    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> ReviewSignHash.from_binary()

    %{review | sign_hash: sign_hash}
  end

  def sync_derive_fields(review), do: review

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, Review,
      accept: [:insert, :update],
      check: &Validation.review_allowed(&1, user_pop_context),
      validate: &Validation.review_validate/3
    )
  end
end
