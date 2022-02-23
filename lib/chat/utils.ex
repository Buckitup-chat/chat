defmodule Chat.Utils do
  @moduledoc "Util functions"
  def hash(data) do
    data
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha3_256, &1))
    |> Base.encode16()
    |> String.downcase()
  end
end
