defmodule Chat.Upload.Upload do
  @moduledoc """
  Upload struct
  """
  defstruct [:secret, :timestamp, :client_size, :client_type, :client_name]
end
