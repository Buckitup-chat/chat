defmodule Chat.Data.Shapes.ReviewPostRight do
  @moduledoc "Shape behaviour implementation for review_post_right."

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPostRight.Validation
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias EnigmaPq
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :review_post_right

  @impl true
  def schema_module, do: ReviewPostRight

  @impl true
  def sync_required_parents(_op, %{author_hash: ah}) do
    [{:user_card, ah}]
  end

  @impl true
  def sync_derive_fields(%ReviewPostRight{sign_b64: sign_b64} = right)
      when is_binary(sign_b64) do
    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> ReviewPostRightSignHash.from_binary()

    %{right | sign_hash: sign_hash}
  end

  def sync_derive_fields(right), do: right

  @impl true
  def sync_persist(operation, right) do
    case operation do
      :insert ->
        right
        |> Validation.validate_post_right_insert()
        |> persist_insert(right)

      :update ->
        persist_update(right)
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, ReviewPostRight,
      accept: [:insert, :update],
      check: &Validation.post_right_allowed(&1, user_pop_context),
      validate: &Validation.post_right_validate/3
    )
  end

  defp persist_insert(changeset, right) do
    case changeset do
      %{valid?: true} ->
        PostRightData.upsert_post_right(changeset)

      %{valid?: false} = cs ->
        log("Invalid review_post_right insert: #{inspect(cs.errors)}", :warning)
        {:ok, right}
    end
  end

  defp persist_update(right) do
    case PostRightData.get_post_right(right.review_hash) do
      nil ->
        {:ok, right}

      existing ->
        existing
        |> Validation.validate_post_right_update(right)
        |> apply_changeset(right)
    end
  end

  defp apply_changeset(changeset, right) do
    case changeset do
      %{valid?: true} ->
        %ReviewPostRight{}
        |> ReviewPostRight.create_changeset(right |> Map.from_struct())
        |> PostRightData.upsert_post_right()

      %{valid?: false, action: :ignore} ->
        {:ok, right}

      %{valid?: false} = cs ->
        log("Invalid review_post_right update: #{inspect(cs.errors)}", :warning)
        {:ok, right}
    end
  end
end
