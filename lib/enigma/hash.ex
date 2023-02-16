defmodule Enigma.Hash do
  @moduledoc """
  Hashing
  """
  @hasher :sha3_256

  def hash(hashable) do
    hashable
    |> Enigma.Hash.Protocol.to_iodata()
    |> binhash()
  end

  def short_hash(hashable) do
    hashable
    |> hash()
    |> then(fn <<code::binary-size(4)>> <> _ -> code end)
    |> Base.encode16(case: :lower)
  end

  defp binhash(data) do
    :crypto.hash(@hasher, data)
  end
end
