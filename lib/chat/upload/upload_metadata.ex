defmodule Chat.Upload.UploadMetadata do
  @moduledoc """
  Data structure for chat file upload.
  Used for any data that doesn't fit into Phoenix.LiveView.UploadEntry.

  Keys:
  - :credentials - tuple ({chunk_key, chunk_secret})
  - :destination - map with the following keys:
    - :dialog (optional)
    - :pub_key - used for destination identification
    - :type - can be either :dialog or :room
  - :upload_key - key for the Chat.Upload.UploadIndex entry
  - :status - either :active or :paused
  """

  defstruct [:credentials, :status, :upload_key, destination: %{}]
end
