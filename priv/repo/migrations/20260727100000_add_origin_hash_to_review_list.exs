defmodule Chat.Repo.Migrations.AddOriginHashToReviewList do
  use Ecto.Migration

  # docs/pq/reqs/pq_reviews.in_progress.md "Contacts": a reader walks a contact's review_list and
  # then needs the review rows themselves. Without origin_hash the only way back is
  # a `review_hash = ANY(...)` filter, which is unique per contact and re-materializes
  # on every new review. With it, the reader reuses the shared
  # `review where origin_hash = $1` shape that every visitor of that origin syncs.

  def up do
    execute("ALTER TABLE review_list ADD COLUMN origin_hash TEXT")

    execute("""
    UPDATE review_list rl
    SET origin_hash = r.origin_hash
    FROM review r
    WHERE r.review_hash = rl.review_hash
    """)

    # A list entry whose review is missing could never have passed
    # ReviewList.Validation (it rejects unknown reviews), and cannot be given a
    # valid origin_hash — there is nothing to preserve.
    execute("DELETE FROM review_list WHERE origin_hash IS NULL")

    execute("ALTER TABLE review_list ALTER COLUMN origin_hash SET NOT NULL")

    execute("""
    ALTER TABLE review_list
      ADD CONSTRAINT review_list_origin_hash_fkey
      FOREIGN KEY (origin_hash) REFERENCES user_cards(user_hash) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE review_list
      ADD CONSTRAINT review_list_origin_hash_format
      CHECK (origin_hash ~ '^u_[a-f0-9]{128}$')
    """)

    execute("CREATE INDEX review_list_origin_hash ON review_list(origin_hash)")
  end

  def down do
    execute("DROP INDEX IF EXISTS review_list_origin_hash")
    execute("ALTER TABLE review_list DROP COLUMN origin_hash")
  end
end
