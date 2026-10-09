defmodule Chat.Data.Shapes.ReviewPasswordCandidate do
  @moduledoc "Shape for review password candidate ingest. Write-only via HTTP, not peer-synced."

  use Chat.Data.Shapes.Shape

  alias Chat.Data.ReviewPasswordCandidate, as: CandidateData
  alias Chat.Data.ReviewPasswordCandidate.Validation
  alias Chat.Data.Schemas.ReviewPasswordCandidate
  alias Chat.Pq.WriteGate
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :review_password_candidate

  @impl true
  def schema_module, do: ReviewPasswordCandidate

  @impl true
  def sync_required_parents(_op, %{author_hash: ah}), do: [{:user_card, ah}]

  @impl true
  def sync_persist(:insert, candidate) do
    %ReviewPasswordCandidate{}
    |> ReviewPasswordCandidate.create_changeset(Map.from_struct(candidate))
    |> CandidateData.insert_candidate()
  end

  def sync_persist(_op, candidate), do: {:ok, candidate}

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, ReviewPasswordCandidate,
      accept: [:insert],
      check:
        WriteGate.and_gate(
          &Validation.candidate_allowed(&1, user_pop_context),
          :review_password_candidate,
          owner: "author_hash"
        ),
      validate: &Validation.candidate_validate/3,
      insert: [
        post_apply: &Validation.candidate_post_apply_promote/3
      ]
    )
  end
end
