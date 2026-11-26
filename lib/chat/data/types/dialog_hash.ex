defmodule Chat.Data.Types.DialogHash do
  @moduledoc "Dialog identifier derived from sorted participant hashes. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.dialog_prefix()

  @doc "`dialog_hash` of the dialog between two users (order-independent)."
  def for_pair(user_hash_a, user_hash_b) do
    [user_hash_a, user_hash_b]
    |> Enum.sort()
    |> Enum.join()
    |> EnigmaPq.hash()
    |> from_binary()
  end
end
