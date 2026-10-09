defmodule Chat.Data.Shapes.Review do
  @moduledoc "Shape behaviour implementation for review."

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.Review.Validation
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewVersion
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Pq.WriteGate
  alias EnigmaPq
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :review

  @impl true
  def schema_module, do: Review

  @impl true
  def versions_schema, do: ReviewVersion

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
  def sync_persist(operation, review) do
    case operation do
      :insert ->
        review
        |> Validation.validate_review_insert()
        |> persist_insert(review)

      :update ->
        persist_update(review)
    end
  end

  defp persist_insert(changeset, review) do
    case changeset do
      %{valid?: true} ->
        upsert_review(changeset, review)

      %{valid?: false} = cs ->
        log("Invalid review insert signature: #{inspect(cs.errors)}", :warning)
        {:ok, review}
    end
  end

  defp upsert_review(changeset, review) do
    case ReviewData.get_review(review.review_hash) do
      nil -> ReviewData.upsert_review(changeset)
      existing -> ReviewData.insert_review_with_conflict(existing, review)
    end
  end

  defp persist_update(review) do
    with existing when not is_nil(existing) <- ReviewData.get_review(review.review_hash),
         %{valid?: true} <- Validation.validate_review_update(existing, review) do
      ReviewData.update_review_with_versioning(existing, review)
    else
      nil ->
        {:ok, review}

      %{valid?: false} = cs ->
        log("Invalid review update signature: #{inspect(cs.errors)}", :warning)
        {:ok, review}
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, Review,
      accept: [:insert, :update],
      check:
        WriteGate.and_gate(&Validation.review_allowed(&1, user_pop_context), :review,
          owner: "author_hash"
        ),
      validate: &Validation.review_validate_with_versioning/3,
      insert: [
        pre_apply: &Validation.review_pre_apply_versioning/3
      ],
      update: [
        pre_apply: &Validation.review_pre_apply_versioning/3
      ]
    )
  end
end
