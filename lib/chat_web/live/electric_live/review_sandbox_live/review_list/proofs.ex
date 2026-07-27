defmodule ChatWeb.ElectricLive.ReviewSandboxLive.ReviewList.Proofs do
  @moduledoc """
  The moderation-proof matrix for a `review_list` row, client side.

  Mirrors `Chat.Data.ReviewList.Validation.verify_proof_by_mode/6`: which of the
  three `*_sign_hash` fields must be present, absent, or may be either.

  The author's own values are the source of truth — the server copies a
  candidate's `sign_hash` verbatim when it promotes, so the hash computed while
  signing is the one that ends up in the table. Shape reads are only a probe:
  they are served from Electric's replicated storage, which lags the Postgres
  commit the server validates against, so an absent row means "not observed yet",
  never "will be rejected". Only a row that is present *and different* proves
  something is wrong.
  """

  @slots [:review_password_sign_hash, :post_right_sign_hash, :revoke_right_sign_hash]

  @requirements %{
    none: %{
      review_password_sign_hash: :required,
      post_right_sign_hash: :forbidden,
      revoke_right_sign_hash: :forbidden
    },
    post: %{
      review_password_sign_hash: :required,
      post_right_sign_hash: :forbidden,
      revoke_right_sign_hash: :required
    },
    pre: %{
      review_password_sign_hash: :optional,
      post_right_sign_hash: :required,
      revoke_right_sign_hash: :required
    }
  }

  @doc "The slot names, in display order."
  def slots, do: @slots

  @doc "`:required` | `:optional` | `:forbidden` for one slot under `mode`."
  def requirement(mode, slot), do: @requirements |> Map.fetch!(mode) |> Map.fetch!(slot)

  @doc """
  The proof map to sign and send for `mode`, taken from the author's own hashes.

  Forbidden slots are dropped rather than set to nil so the caller can omit them
  from the wire payload — the server reconstructs them as nil either way.

  An *optional* slot is sent only once the shape confirms it (`:ok`). This is
  what keeps a pre-mode insert legal: the author holds
  `review_password_sign_hash` from the moment they sign the candidate, but until
  the origin approves there is no `review_public_passwords` row to point at, and
  `optional_password_proof/3` rejects a hash that resolves to nothing.
  """
  def fields(mode, local, status) do
    @slots
    |> Enum.filter(&send_slot?(requirement(mode, &1), status[&1]))
    |> Map.new(&{&1, local[&1]})
    |> Enum.reject(fn {_slot, hash} -> is_nil(hash) end)
    |> Map.new()
  end

  defp send_slot?(:forbidden, _status), do: false
  defp send_slot?(:optional, status), do: status == :ok
  defp send_slot?(:required, _status), do: true

  @doc """
  Per-slot verdicts comparing what the author signed against what the shape shows.

  - `:not_applicable` — forbidden for this mode
  - `:missing` — required, but the author never captured it
  - `:pending` — captured, not observed in the shape yet (lag, or awaiting the origin)
  - `:ok` — observed and identical
  - `:mismatch` — observed but different: the server promoted a row the author did not sign
  """
  def status(mode, observed, local) do
    Map.new(@slots, &{&1, slot_status(requirement(mode, &1), observed[&1], local[&1])})
  end

  @doc """
  True when nothing in `status/3` should stop the author from submitting.

  Only `:missing` (nothing to reference) and `:mismatch` (the server promoted a
  row the author did not sign) block. `:pending` does not: the server checks
  Postgres directly, which is ahead of the shape we read.
  """
  def submittable?(status),
    do: not Enum.any?(status, fn {_slot, s} -> s in ~w(missing mismatch)a end)

  @doc "True once the origin's approval is visible — pre mode's gate for the fill-in update."
  def password_published?(status), do: status.review_password_sign_hash == :ok

  defp slot_status(:forbidden, _observed, _local), do: :not_applicable
  defp slot_status(:optional, _observed, nil), do: :not_applicable
  defp slot_status(:required, _observed, nil), do: :missing
  defp slot_status(_requirement, nil, _local), do: :pending
  defp slot_status(_requirement, same, same), do: :ok
  defp slot_status(_requirement, _observed, _local), do: :mismatch
end
