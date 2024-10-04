defmodule Chat.Sync.UsbDriveDumpProgress do
  @moduledoc """
  Data structure used to show USB drive dump progress
  """
  use StructAccess

  defstruct completed_size: 0,
            current_file: 0,
            current_filename: "",
            percentage: 0,
            total_files: 0,
            total_size: 0
end
