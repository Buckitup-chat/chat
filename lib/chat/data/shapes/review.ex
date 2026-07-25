defmodule Chat.Data.Shapes.Review do
  @moduledoc "Shape behaviour implementation for review."

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.Review.Validation
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Types.ReviewSignHash
  alias EnigmaPq
  alias Phoenix.Sync.Writer

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

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, Review,
      accept: [:insert, :update],
      check: &Validation.review_allowed(&1, user_pop_context),
      validate: &Validation.review_validate/3
    )
  end

  defp persist_insert(changeset, review) do
    case changeset do
      %{valid?: true} ->
        ReviewData.upsert_review(changeset)

      %{valid?: false} = cs ->
        log("Invalid review insert: #{inspect(cs.errors)}", :warning)
        {:ok, review}
    end
  end

  defp persist_update(review) do
    case ReviewData.get_review(review.review_hash) do
      nil ->
        {:ok, review}

      existing ->
        existing
        |> Validation.validate_review_update(review)
        |> apply_changeset(review)
    end
  end

  defp apply_changeset(changeset, review) do
    case changeset do
      %{valid?: true} ->
        %Review{}
        |> Review.create_changeset(review |> Map.from_struct())
        |> ReviewData.upsert_review()

      %{valid?: false, action: :ignore} ->
        {:ok, review}

      %{valid?: false} = cs ->
        log("Invalid review update: #{inspect(cs.errors)}", :warning)
        {:ok, review}
    end
  end
end
