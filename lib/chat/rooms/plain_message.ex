defmodule Chat.Rooms.PlainMessage do
  @moduledoc "Plain room message"

  defstruct [:author_hash, :content, :type, :timestamp, :id]
end
