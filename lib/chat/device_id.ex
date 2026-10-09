defmodule Chat.DeviceId do
  @moduledoc "Device identity for vouch token scopes (device.<id>.*)"

  @callback id() :: String.t()

  def id do
    impl().id()
  end

  defp impl do
    Application.get_env(:chat, :device_id_module, Chat.DeviceId.Default)
  end
end
