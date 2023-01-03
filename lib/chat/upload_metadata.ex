defmodule Chat.UploadMetadata do
  @moduledoc """
  Data structure for chat file upload.
  Used for any data that doesn't fit into Phoenix.LiveView.UploadEntry.

  Keys:
  - :credentials - tuple ({chunk_key, chunk_secret})
  - :destination - map with the following keys:
    - :dialog (optional)
    - :pub_key - used for destination identification
    - :type - can be either :dialog or :room
  """

  defstruct [:credentials, destination: %{}]
end
