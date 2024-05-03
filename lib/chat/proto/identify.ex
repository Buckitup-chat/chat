defprotocol Chat.Proto.Identify do
  def pub_key(identity)
end

defimpl Chat.Proto.Identify, for: Chat.Card do
  def pub_key(%Chat.Card{pub_key: pub_key}), do: pub_key
end

defimpl Chat.Proto.Identify, for: Chat.Identity do
  def pub_key(%Chat.Identity{public_key: pub_key}), do: pub_key
end

defimpl Chat.Proto.Identify, for: Chat.Rooms.Room do
  def pub_key(%Chat.Rooms.Room{pub_key: pub_key}), do: pub_key
end

defimpl Chat.Proto.Identify, for: BitString do
  def pub_key(pub_key), do: pub_key
end
