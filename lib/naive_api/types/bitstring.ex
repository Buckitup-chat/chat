defmodule NaiveApi.Types.Bitstring do
  @moduledoc """
  Bitstring conversion fuctions
  """

  def parse(encoded), do: encoded |> Base.url_decode64()
  def parse_32(<<encoded::binary-size(64)>>), do: encoded |> Base.decode16(case: :lower)
  def parse_33(<<encoded::binary-size(66)>>), do: encoded |> Base.decode16(case: :lower)

  def serialize(raw), do: raw |> Base.url_encode64()
  def serialize_32(<<raw::binary-size(32)>>), do: raw |> Base.encode16(case: :lower)
  def serialize_33(<<raw::binary-size(33)>>), do: raw |> Base.encode16(case: :lower)
end
