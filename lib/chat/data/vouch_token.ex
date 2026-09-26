defmodule Chat.Data.VouchToken do
  @moduledoc "Data access for vouch_tokens."

  alias Chat.Data.Schemas.VouchToken
  alias Chat.Repo

  @default_max_depth 7

  def resource_forest do
    %{
      "device" => %{
        :device_id => %{
          "storage" => %{
            "read" => :shape,
            "write" => :shape
          },
          "admin" => %{}
        }
      },
      "origins" => %{
        :origin_hash => %{
          "reviews" => %{
            "write" => :review_token
          }
        }
      }
    }
  end

  def get_vouch_token(kind, issuer_hash, subject_hash) do
    Repo.get_by(VouchToken, kind: kind, issuer_hash: issuer_hash, subject_hash: subject_hash)
  end

  def chain_distance(owner_hash, subject_hash, scope_prefix, max_depth \\ @default_max_depth) do
    [root_segment | _] = String.split(scope_prefix, ".")

    params = [owner_hash, scope_prefix, max_depth, subject_hash, root_segment]

    case Repo.query(chain_distance_sql(), params) do
      {:ok, %{rows: [[distance]]}} when is_integer(distance) -> {:ok, distance}
      {:ok, _} -> :unreachable
    end
  end

  defp chain_distance_sql do
    """
    WITH RECURSIVE trust_chain AS (
      SELECT
        vt.subject_hash                AS user_hash,
        1                              AS distance,
        scope_intersect($2, vt.kind)   AS effective_scope,
        false                          AS widened
      FROM vouch_tokens vt
      WHERE vt.issuer_hash  = $1
        AND (vt.kind = $5 OR vt.kind LIKE $5 || '.%')
        AND scope_intersect($2, vt.kind) IS NOT NULL
        AND vt.deleted_flag = false
        AND NOT EXISTS (
          SELECT 1 FROM vouch_tokens t
          WHERE t.issuer_hash  = vt.issuer_hash
            AND t.subject_hash = vt.subject_hash
            AND t.deleted_flag = true
            AND scope_narrower_or_eq(vt.kind, t.kind)
        )

      UNION ALL

      SELECT
        vt.subject_hash,
        tc.distance + 1,
        scope_intersect(tc.effective_scope, vt.kind),
        tc.widened OR NOT scope_narrower_or_eq(vt.kind, tc.effective_scope)
      FROM vouch_tokens vt
      JOIN trust_chain tc ON vt.issuer_hash = tc.user_hash
      WHERE (vt.kind = $5 OR vt.kind LIKE $5 || '.%')
        AND scope_intersect(tc.effective_scope, vt.kind) IS NOT NULL
        AND vt.deleted_flag = false
        AND tc.distance     < $3
        AND NOT EXISTS (
          SELECT 1 FROM vouch_tokens t
          WHERE t.issuer_hash  = vt.issuer_hash
            AND t.subject_hash = vt.subject_hash
            AND t.deleted_flag = true
            AND scope_narrower_or_eq(vt.kind, t.kind)
        )
    )
    CYCLE user_hash SET is_cycle USING path

    SELECT MIN(distance) AS chain_distance
    FROM trust_chain
    WHERE NOT is_cycle
      AND user_hash = $4
      AND (
        (NOT widened AND (scope_narrower_or_eq(effective_scope, $2)
                          OR scope_narrower_or_eq($2, effective_scope)))
        OR
        (widened AND scope_narrower_or_eq($2, effective_scope))
      )
      AND NOT EXISTS (
        SELECT 1 FROM vouch_tokens t
        WHERE t.issuer_hash  = $1
          AND t.subject_hash = $4
          AND t.deleted_flag = true
          AND scope_narrower_or_eq($2, t.kind)
      )
    """
  end

  def upsert_vouch_token(changeset) do
    Repo.insert(changeset,
      on_conflict: :replace_all,
      conflict_target: [:kind, :issuer_hash, :subject_hash]
    )
  end
end
