defmodule ChatWeb.Plugs.HexToBase64Electric do
  @moduledoc "Forwards to Phoenix.Sync.Electric with hex-to-base64 adapter wrapping, unwrapping before returning to cowboy."

  alias ChatWeb.Plugs.HexToBase64Adapter
  alias Phoenix.Sync.Electric, as: SyncElectric

  def init(opts), do: SyncElectric.init(opts)

  def call(conn, opts) do
    conn
    |> HexToBase64Adapter.wrap()
    |> SyncElectric.call(opts)
    |> HexToBase64Adapter.unwrap()
  end
end
