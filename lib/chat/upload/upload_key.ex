defmodule Chat.Upload.UploadKey do
  @moduledoc "Forms the upload key"

  @type entry ::
          %{
            client_last_modified: integer() | nil,
            client_name: String.t() | nil,
            client_relative_path: String.t() | nil,
            client_size: integer() | nil,
            client_type: String.t() | nil
          }
          | Phoenix.LiveView.UploadEntry.t()

  @spec new(map(), String.t(), entry()) :: <<_::32>>
  def new(destination, client_id, entry) do
    encoded_destination =
      destination
      |> Jason.encode!()
      |> Base.encode64()

    [
      client_id,
      encoded_destination,
      entry.client_relative_path,
      entry.client_name,
      entry.client_type,
      entry.client_size,
      entry.client_last_modified
    ]
    |> Enum.join(":")
    |> Enigma.hash()
  end
end
