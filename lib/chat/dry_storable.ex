defprotocol Chat.DryStorable do
  @spec content(t) :: String.t()
  def content(storable)

  @spec timestamp(t) :: String.t()
  def timestamp(storable)

  @spec type(t) :: any()
  def type(storable)
end
