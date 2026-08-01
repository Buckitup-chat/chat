defmodule Chat.Data.Shapes.ReviewList do
  @moduledoc "Shape behaviour implementation for review_list."

  alias Chat.Data.ReviewList, as: ReviewListData
  alias Chat.Data.ReviewList.Validation
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Types.ReviewListSignHash
  alias EnigmaPq
  alias Phoenix.Sync.Writer

  use Chat.Data.Shapes.Shape,
    persist: [
      upsert: &ReviewListData.upsert_review_list_entry/1,
      get: &ReviewListData.get_review_list_entry/2,
      lookup_key: [:user_hash, :review_hash],
      validate_insert: &Validation.validate_review_list_insert/1,
      validate_update: &Validation.validate_review_list_update/2
    ]

  use Toolbox.OriginLog

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
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, ReviewList,
      accept: [:insert, :update],
      check: &Validation.review_list_allowed(&1, user_pop_context),
      validate: &Validation.review_list_validate/3
    )
  end
end
