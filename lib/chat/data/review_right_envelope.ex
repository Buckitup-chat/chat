defmodule Chat.Data.ReviewRightEnvelope do
  @moduledoc """
  HKDF context for the review right envelope — the AES-GCM wrapper around a
  `review_public_passwords` row carried by right candidates and, after
  promotion, by `review_post_rights` / `review_revoke_rights`.

  The wrapping side (promotion) and every unwrapping side (author verification,
  origin moderation, fixtures) must derive the same key from the KEM shared
  secret, so the context and label live here only and the derivation is done
  through `wrap_key/1`.
  """

  alias EnigmaPq

  @context "buckitup/review-right/v1"
  @label "wrap"

  @doc "Derives the AES-GCM wrap key for a right envelope from a KEM shared secret."
  def wrap_key(shared_secret), do: EnigmaPq.hkdf_derive(shared_secret, @context, @label)
end
