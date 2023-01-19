defimpl Jason.Encoder, for: Tuple do
  def encode(tuple, opts) do
    Jason.Encode.list(Tuple.to_list(tuple), opts)
  end
end
