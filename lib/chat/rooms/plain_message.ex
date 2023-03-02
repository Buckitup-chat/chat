defmodule Chat.Rooms.PlainMessage do
  @moduledoc "Plain room message"

  defstruct [:author_key, :content, :type, :timestamp, :id, :index]
end
