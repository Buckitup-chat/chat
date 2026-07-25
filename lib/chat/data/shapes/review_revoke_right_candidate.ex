defmodule Chat.Data.Shapes.ReviewRevokeRightCandidate do
  @moduledoc "Shape for review revoke right candidate. Server-created, client signs via ingest update."

  use Chat.Data.Shapes.Shape

  alias Chat.Data.ReviewRightCandidate.Validation
  alias Chat.Data.Schemas.ReviewRevokeRightCandidate
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :review_revoke_right_candidate

  @impl true
  def schema_module, do: ReviewRevokeRightCandidate

  @impl true
  def sync_required_parents(_op, %{author_hash: ah}), do: [{:user_card, ah}]

  @impl true
  def sync_persist(_op, candidate), do: {:ok, candidate}

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, ReviewRevokeRightCandidate,
      accept: [:update],
      check: &Validation.right_candidate_check/1,
      validate: fn s, c, o ->
        Validation.revoke_right_candidate_validate(s, c, o, user_pop_context)
      end,
      update: [
        post_apply: &Validation.right_candidate_post_apply_complete/3
      ]
    )
  end
end
