defprotocol Enigma.Hash.Protocol do
  @spec to_iodata(t) :: iodata()
  def to_iodata(value)
end

defimpl Enigma.Hash.Protocol, for: BitString do
  def to_iodata(str), do: str
end
