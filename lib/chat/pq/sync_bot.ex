defmodule Chat.Pq.SyncBot do
  @moduledoc "The SyncBot card: the user_card of a device's server identity, synced and pushed to peers."

  alias Chat.DeviceId

  @prefix "SyncBot_"

  @doc "The name of this device's SyncBot card."
  def card_name, do: @prefix <> DeviceId.id()

  @doc "Whether `card` is a device's SyncBot card: every device names its own `SyncBot_<device_id>`."
  def card?(%{name: name}) when is_binary(name), do: String.starts_with?(name, @prefix)
  def card?(_card), do: false
end
