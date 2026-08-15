defmodule Chat.Data.File.DriveDirs do
  @moduledoc """
  Directory layout for drive-attached chunk file storage.

  Single source of truth for:
    - the internal drive's own chunk-files directory (independent of whichever
      drive is currently active for writes)
    - a USB drive's chunk-files directory, given its mount path
    - the media root USB drives are mounted under, and discovery of the
      chunk-file directories of currently attached USB drives

  The media root is owned by `platform` (`config :platform, :mount_path_media`)
  but mirrored into `config :chat, :usb_media_root` so this module - and the
  chat app generally - doesn't reach across the dependency boundary. It's
  `nil` for standalone chat (no USB drives to discover).
  """

  @main_db_dir "main_db"
  @files_suffix "_files"
  @pq_files_dir "pq_files"

  def internal_files_dir, do: Chat.Db.file_path() <> @files_suffix

  def usb_files_dir(mount_path),
    do: Path.join([mount_path, @main_db_dir, Chat.Db.version_path()]) <> @files_suffix

  def media_root, do: Application.get_env(:chat, :usb_media_root)

  @doc "Chunk-file directories of currently attached USB drives, as `{device, base_dir}` pairs."
  def list_usb_drive_dirs do
    case media_root() do
      nil -> []
      root -> root |> Path.join("sd*") |> Path.wildcard() |> Enum.flat_map(&drive_dir_entry/1)
    end
  end

  defp drive_dir_entry(device_path) do
    base_dir = usb_files_dir(device_path)

    if File.dir?(Path.join(base_dir, @pq_files_dir)) do
      [{Path.basename(device_path), base_dir}]
    else
      []
    end
  end
end
