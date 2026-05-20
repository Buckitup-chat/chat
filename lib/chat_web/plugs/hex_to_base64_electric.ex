defmodule ChatWeb.Plugs.HexToBase64Electric do
  @moduledoc "Forwards to Phoenix.Sync.Electric with hex-to-base64 adapter wrapping, unwrapping before returning to cowboy."

  alias ChatWeb.Plugs.HexToBase64Adapter

  def init(opts), do: Phoenix.Sync.Electric.init(opts)

  def call(conn, opts) do
    conn
    |> HexToBase64Adapter.wrap()
    |> Phoenix.Sync.Electric.call(opts)
    |> HexToBase64Adapter.unwrap()
  end
end
