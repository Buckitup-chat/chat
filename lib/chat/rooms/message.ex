defmodule Chat.Rooms.Message do
  @moduledoc "Room message struct"

  defstruct [:timestamp, :author_hash, :encrypted, :type, :id, version: 1]

  def new(encrypted, author, opts) do
    id = opts |> Keyword.get(:id, UUID.uuid4())
    now = opts |> Keyword.get(:now, DateTime.utc_now())
    type = opts |> Keyword.get(:type, :text)

    %__MODULE__{
      timestamp: now |> unixtime(),
      author_hash: author,
      encrypted: encrypted,
      type: type,
      id: id
    }
  end

  defp unixtime(%DateTime{} = time), do: time |> DateTime.to_unix()
  defp unixtime(time), do: time
end
