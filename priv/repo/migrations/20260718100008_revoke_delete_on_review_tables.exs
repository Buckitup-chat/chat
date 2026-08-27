defmodule Chat.Repo.Migrations.RevokeDeleteOnReviewTables do
  use Ecto.Migration

  # Enforces the append-only guarantee from docs/pq/reqs/pg_constraints.md §5 and
  # docs/pq/reqs/pq_reviews.in_progress.md "Row immutability": content tables must never lose
  # rows, so a rogue origin — or the server — cannot delete reviews or moderation
  # records. Visibility is controlled exclusively via review_public_passwords
  # versioning (publish/revoke by timestamp), never by row deletion.
  #
  # NOTE: table-level REVOKE only binds a NON-superuser role. The app currently
  # connects as the `postgres` superuser (config/{dev,test}.exs), which bypasses
  # table privileges, so this is effectively a no-op until a dedicated limited
  # role is introduced (Phase 3 / platform). Revoking from PUBLIC documents the
  # intent and becomes effective the moment the app connects via a limited role;
  # at that point add `REVOKE DELETE ON <t> FROM <app_role>` here too.
  #
  # Candidate/staging tables (review_password_candidate, review_*_right_candidate)
  # are intentionally excluded — they must remain deletable for garbage collection.

  @tables ~w(review review_public_passwords review_post_right review_revoke_right review_list)

  def up do
    for table <- @tables do
      execute("REVOKE DELETE ON #{table} FROM PUBLIC")
    end
  end

  def down do
    for table <- @tables do
      execute("GRANT DELETE ON #{table} TO PUBLIC")
    end
  end
end
