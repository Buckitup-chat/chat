defmodule Chat.Dialogs.PrivateMessage do
  @moduledoc "Represents decrypted message for a peer"

  @type t :: %__MODULE__{}

  defstruct [:timestamp, :index, :type, :content, :is_mine?, :id]
end
