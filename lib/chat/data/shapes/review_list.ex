defmodule Chat.Data.Shapes.ReviewList do
  @moduledoc "Shape behaviour implementation for review_list."

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.ReviewList, as: ReviewListData
  alias Chat.Data.ReviewList.Validation
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Types.ReviewListSignHash
  alias EnigmaPq
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :review_list

  @impl true
  def schema_module, do: ReviewList

  @impl true
  def sync_required_parents(_op, %{user_hash: uh}) do
    [{:user_card, uh}]
  end

  @impl true
  def sync_derive_fields(%ReviewList{sign_b64: sign_b64} = rl) when is_binary(sign_b64) do
    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> ReviewListSignHash.from_binary()

    %{rl | sign_hash: sign_hash}
  end

  def sync_derive_fields(rl), do: rl

  @impl true
  def sync_persist(operation, rl) do
    case operation do
      :insert ->
        rl
        |> Validation.validate_review_list_insert()
        |> persist_insert(rl)

      :update ->
        persist_update(rl)
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, ReviewList,
      accept: [:insert, :update],
      check: &Validation.review_list_allowed(&1, user_pop_context),
      validate: &Validation.review_list_validate/3
    )
  end

  defp persist_insert(changeset, rl) do
    case changeset do
      %{valid?: true} ->
        ReviewListData.upsert_review_list_entry(changeset)

      %{valid?: false} = cs ->
        log("Invalid review_list insert: #{inspect(cs.errors)}", :warning)
        {:ok, rl}
    end
  end

  defp persist_update(rl) do
    case ReviewListData.get_review_list_entry(rl.user_hash, rl.review_hash) do
      nil ->
        {:ok, rl}

      existing ->
        existing
        |> Validation.validate_review_list_update(rl)
        |> apply_changeset(rl)
    end
  end

  defp apply_changeset(changeset, rl) do
    case changeset do
      %{valid?: true} ->
        %ReviewList{}
        |> ReviewList.create_changeset(rl |> Map.from_struct())
        |> ReviewListData.upsert_review_list_entry()

      %{valid?: false} = cs ->
        log("Invalid review_list update: #{inspect(cs.errors)}", :warning)
        {:ok, rl}
    end
  end
end
