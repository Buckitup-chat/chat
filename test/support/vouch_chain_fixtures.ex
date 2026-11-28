defmodule Chat.Test.VouchChainFixtures do
  @moduledoc """
  Owner / Alice / Bob / Carol vouch graphs for the `chain_distance_*` tests. Parties are
  addressed by name (`:owner`, `:alice`, `:bob`, `:carol`) in `vouch/5` and `distance/4,5`.
  """

  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1, sign_with_key: 2]

  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData

  @doc """
  Setup: clears deferred records, inserts signed user cards for the four parties and returns
  `identities` and `hashes`, both keyed by party name.
  """
  def vouch_parties(_ctx) do
    :ets.delete_all_objects(:buckitup_deferred_records)

    identities = %{
      owner: User.generate_pq_identity("Owner"),
      alice: User.generate_pq_identity("Alice"),
      bob: User.generate_pq_identity("Bob"),
      carol: User.generate_pq_identity("Carol")
    }

    hashes =
      Map.new(identities, fn {name, identity} -> {name, insert_user_card(identity).user_hash} end)

    {:ok, identities: identities, hashes: hashes}
  end

  @doc """
  Upserts a vouch token of `kind` from `issuer` to `subject`, signed by the issuer.
  Options: `:deleted_flag` (tombstone), `:ts` (owner timestamp).
  """
  def vouch(ctx, issuer, subject, kind, opts \\ []) do
    vt =
      %VouchToken{
        kind: kind,
        issuer_hash: ctx.hashes[issuer],
        subject_hash: ctx.hashes[subject],
        owner_timestamp: Keyword.get(opts, :ts, System.os_time(:millisecond)),
        deleted_flag: Keyword.get(opts, :deleted_flag, false)
      }
      |> sign_with_key(ctx.identities[issuer].sign_skey)

    {:ok, _} =
      VouchTokenData.upsert_vouch_token(
        VouchToken.create_changeset(%VouchToken{}, Map.from_struct(vt))
      )
  end

  @doc "`VouchTokenData.chain_distance/3` between two parties."
  def distance(ctx, from, to, scope),
    do: VouchTokenData.chain_distance(ctx.hashes[from], ctx.hashes[to], scope)

  @doc "`VouchTokenData.chain_distance/4` between two parties, limited to `max_depth` hops."
  def distance(ctx, from, to, scope, max_depth),
    do: VouchTokenData.chain_distance(ctx.hashes[from], ctx.hashes[to], scope, max_depth)
end
