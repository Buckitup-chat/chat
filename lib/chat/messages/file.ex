defmodule Chat.Messages.File do
  @moduledoc "File and image message"

  defstruct data: [], timestamp: 0, type: :file

  @max_image_size 30_000_000

  @type t :: %__MODULE__{}

  def new(entry, chunk_key, chunk_secret) do
    mime_type = entry.client_type |> mime_type()

    type =
      cond do
        match?("audio/" <> _, mime_type) -> :audio
        match?("image/" <> _, mime_type) and entry.client_size < @max_image_size -> :image
        match?("video/" <> _, mime_type) -> :video
        true -> :file
      end

    %__MODULE__{
      data: [
        chunk_key,
        chunk_secret |> Base.encode64(),
        entry.client_size |> to_string(),
        entry.client_type |> mime_type(),
        entry.client_name,
        entry.client_size |> format_size()
      ],
      type: type
    }
  end

  def new(entry, chunk_key, chunk_secret, timestamp) do
    entry
    |> new(chunk_key, chunk_secret)
    |> Map.put(:timestamp, timestamp)
  end

  def mime_type(nil), do: "application/octet-stream"
  def mime_type(""), do: mime_type(nil)
  def mime_type(x), do: x

  def format_size(n) when n > 1_000_000_000, do: "#{trunc(n / 100_000_000) / 10} Gb"
  def format_size(n) when n > 1_000_000, do: "#{trunc(n / 100_000) / 10} Mb"
  def format_size(n) when n > 1_000, do: "#{trunc(n / 100) / 10} Kb"
  def format_size(n), do: "#{n} b"
end

defimpl Chat.DryStorable, for: Chat.Messages.File do
  alias Chat.Content.Files
  alias Chat.Messages.File
  alias Chat.Utils.StorageId

  def content(%File{} = msg) do
    msg.data
    |> Files.add()
    |> StorageId.to_json()
  end

  def timestamp(%File{} = msg), do: msg.timestamp

  @spec type(File.t()) :: atom()
  def type(%File{type: type}), do: type

  # TODO: make proper parcel
  def to_parcel(%File{} = msg), do: {msg.data, []}
end
