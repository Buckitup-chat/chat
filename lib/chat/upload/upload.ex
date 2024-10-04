defmodule Chat.Upload.Upload do
  @moduledoc """
  Upload struct
  """
  defstruct [:encrypted_secret, :timestamp, :client_size, :client_type, :client_name]
end
