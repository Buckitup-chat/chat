defmodule Chat.Data.Types.ReviewWriteTokenNonceHash do
  @moduledoc """
  Hash of a review write token nonce (`rwn_` + SHA3-512). Custom Ecto type.

  The row key, the vouch kind and every lookup use this hash; the plaintext
  nonce never leaves create/bind responses, `/r/<nonce>` and review `auth.nonce`.
  """

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash,
    prefix: Consts.review_write_token_nonce_prefix()

  def from_nonce(nonce) when is_binary(nonce) do
    nonce
    |> EnigmaPq.hash()
    |> from_binary()
  end
end
