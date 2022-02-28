defmodule Chat.Rooms.Message do
  @moduledoc "Room message struct"

  defstruct [:timestamp, :author_hash, :encrypted, :type]

  def new(author, encrypted, opts) do
    now = opts |> Keyword.get(:now, DateTime.utc_now())
    type = opts |> Keyword.get(:type, :text)

    %__MODULE__{
      timestamp: now |> DateTime.to_unix(),
      author_hash: author,
      encrypted: encrypted,
      type: type
    }
  end
end
