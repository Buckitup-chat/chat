defprotocol Chat.DryStorable do
  @spec content(t) :: String.t()
  def content(storable)

  @spec timestamp(t) :: String.t()
  def timestamp(storable)

  @spec type(t) :: any()
  def type(storable)

  @spec to_parcel(t) :: {any(), list()}
  def to_parcel(storable)
end
