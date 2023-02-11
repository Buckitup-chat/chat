defmodule Enigma.Hash do
  @moduledoc """
  Hashing
  """
  @hasher :sha3_256

  def hash(hashable) do
    hashable
    |> Enigma.Hash.Protocol.to_iodata()
    |> maybe_binhash()
    |> Base.encode16(case: :lower)
  end

  def short_hash(hashable) do
    hashable
    |> binhash()
    |> then(fn <<code::binary-size(4)>> <> _ -> code end)
    |> Base.encode16(case: :lower)
  end

  def binhash(hashable) do
    hashable
    |> Enigma.Hash.Protocol.to_iodata()
    |> maybe_binhash()
  end

  defp maybe_binhash(data) do
    :crypto.hash(@hasher, data)
  end
end
