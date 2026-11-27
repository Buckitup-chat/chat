defmodule Chat.Data.ReviewCandidateCleanerTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.ReviewCandidateCleaner
  alias Chat.Data.Schemas.ReviewPasswordCandidate
  alias Chat.Data.Schemas.ReviewPostRightCandidate
  alias Chat.Data.Schemas.ReviewRevokeRightCandidate
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User
  alias Chat.Test.ReviewFixtures
  alias Ecto.Adapters.SQL.Sandbox

  @max_age 3600
  @newest 10_000_000

  @schemas [ReviewPasswordCandidate, ReviewPostRightCandidate, ReviewRevokeRightCandidate]

  describe "handle_info(:cleanup)" do
    test "deletes candidates older than an hour behind the author's newest one" do
      author = insert_author("Alice")

      ids =
        for schema <- @schemas, into: %{} do
          {schema,
           %{
             newest: insert_candidate(schema, author, @newest),
             fresh: insert_candidate(schema, author, @newest - @max_age + 1),
             at_cutoff: insert_candidate(schema, author, @newest - @max_age),
             stale: insert_candidate(schema, author, @newest - @max_age - 1)
           }}
        end

      run_cleanup()

      for {schema, %{stale: stale} = rows} <- ids do
        refute present?(schema, stale)
        assert present?(schema, rows.newest)
        assert present?(schema, rows.fresh)
        assert present?(schema, rows.at_cutoff)
      end
    end

    test "measures age per author" do
      busy_author = insert_author("Busy")
      quiet_author = insert_author("Quiet")

      rows =
        for schema <- @schemas do
          insert_candidate(schema, busy_author, @newest)

          {schema, insert_candidate(schema, busy_author, @newest - 2 * @max_age),
           insert_candidate(schema, quiet_author, @newest - 2 * @max_age)}
        end

      run_cleanup()

      for {schema, busy_stale, quiet} <- rows do
        refute present?(schema, busy_stale)
        assert present?(schema, quiet)
      end
    end
  end

  defp run_cleanup do
    pid = start_supervised!({ReviewCandidateCleaner, name: nil})

    Sandbox.allow(Repo, self(), pid)
    send(pid, :cleanup)
    :sys.get_state(pid)
  end

  defp present?(schema, review_hash), do: Repo.get_by(schema, review_hash: review_hash) != nil

  defp insert_candidate(ReviewPasswordCandidate, author_hash, owner_timestamp) do
    review_hash = random_review_hash()

    Repo.insert!(%ReviewPasswordCandidate{
      review_hash: review_hash,
      sign_hash: :crypto.strong_rand_bytes(64) |> ReviewPasswordSignHash.from_binary(),
      origin_hash: random_user_hash(),
      author_hash: author_hash,
      owner_timestamp: owner_timestamp,
      sign_b64: :crypto.strong_rand_bytes(64)
    })

    review_hash
  end

  defp insert_candidate(schema, author_hash, owner_timestamp) do
    review_hash = random_review_hash()

    schema
    |> struct(%{
      review_hash: review_hash,
      origin_hash: random_user_hash(),
      author_hash: author_hash,
      kem_ciphertext_b64: "kem",
      wrapped_row_b64: "row",
      owner_timestamp: owner_timestamp,
      inserted_at: owner_timestamp
    })
    |> Repo.insert!()

    review_hash
  end

  defp insert_author(name) do
    name
    |> User.generate_pq_identity()
    |> ReviewFixtures.insert_user_card()
    |> Map.fetch!(:user_hash)
  end

  defp random_review_hash, do: :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
  defp random_user_hash, do: :crypto.strong_rand_bytes(64) |> UserHash.from_binary()
end
