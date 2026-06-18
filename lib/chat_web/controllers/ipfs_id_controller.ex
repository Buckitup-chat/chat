defmodule ChatWeb.IpfsIdController do
  use ChatWeb, :controller

  alias Chat.Data.File.IpfsStore

  def show(conn, _params) do
    case IpfsStore.peer_id() do
      {:ok, %{peer_id: id, multiaddrs: addrs}} ->
        json(conn, %{peer_id: id, multiaddrs: addrs})

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "IPFS daemon not available"})
    end
  end
end
