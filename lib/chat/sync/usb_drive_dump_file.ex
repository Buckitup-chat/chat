defmodule Chat.Sync.UsbDriveDumpFile do
  @moduledoc """
  File data structure for USB drive dump.
  """

  defstruct [:datetime, :name, :path, :size]
end
