defmodule Chat.Dialogs.PrivateMessage do
  @moduledoc "Represents decrypted message for a peer"

  defstruct [:timestamp, :index, :type, :content, :is_mine?, :id]
end
