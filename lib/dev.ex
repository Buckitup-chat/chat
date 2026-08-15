defmodule Dev do
  @moduledoc "Device functions "

  def path(device, role, resource) do
    [device_base_path(device, role), resource_path(resource)]
    |> Path.join()
  end

  defp device_base_path(device, role) do
    case {device, role} do
      {"sd" <> _, role} -> [media_root(), device, role]
      {:internal, role} -> [internal_root(), role]
    end
    |> Path.join()
  end

  defp resource_path(resource) do
    case resource do
      :cub_db -> [db_version()]
      :cub_files -> [db_version() <> "_files"]
      :pg_db -> ["pg"]
      :pg_files -> ["files"]
    end
    |> Path.join()
  end

  @mount_path Application.compile_env(:platform, :mount_path_media, "priv/media")
  defp media_root, do: @mount_path

  @internal_root Application.compile_env(:chat, :internal_root, "priv")
  defp internal_root, do: @internal_root

  defp db_version, do: Chat.Db.version_path()
end
