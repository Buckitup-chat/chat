defmodule Chat.Dialogs.PrivateMessage do
  @moduledoc "Represents decrypted message for a peer"

  defstruct [:timestamp, :type, :content, :is_mine?]
end
