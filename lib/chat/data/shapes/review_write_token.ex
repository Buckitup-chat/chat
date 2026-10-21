defmodule Chat.Data.Shapes.ReviewWriteToken do
  @moduledoc "Shape behaviour implementation for review_write_token."

  alias Chat.Data.ReviewWriteToken, as: ReviewWriteTokenData
  alias Chat.Data.ReviewWriteToken.Validation
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Pq.WriteGate
  alias Phoenix.Sync.Writer

  use Chat.Data.Shapes.Shape,
    persist: [
      upsert: &ReviewWriteTokenData.upsert_review_write_token/1,
      get: &ReviewWriteTokenData.get_review_write_token/1,
      lookup_key: :nonce,
      validate_insert: &Validation.validate_review_write_token_insert/1,
      validate_update: &Validation.validate_review_write_token_update/2
    ]

  use Toolbox.OriginLog

  @impl true
  def shape_name, do: :review_write_token

  @impl true
  def schema_module, do: ReviewWriteToken

  @impl true
  def sync_required_parents(_op, %{origin_hash: oh, review_bot_hash: bh}) do
    [{:user_card, oh}, {:origin, oh}, {:user_card, bh}]
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, ReviewWriteToken,
      accept: [:insert, :update],
      check:
        WriteGate.and_gate(
          &Validation.review_write_token_allowed(&1, user_pop_context),
          :review_write_token,
          owner: "review_bot_hash"
        ),
      validate: &Validation.review_write_token_validate/3
    )
  end
end
