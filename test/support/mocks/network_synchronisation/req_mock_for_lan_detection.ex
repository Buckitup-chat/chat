defmodule ChatSupport.Mocks.NetworkSynchronization.ReqMockForLanDetection do
  @moduledoc "Mocking Req for LAN Electric peer detection"

  @electric_peers ["10.10.10.111", "10.10.10.20"]

  def electric_peers_list, do: @electric_peers

  def get(url, _opts \\ []) do
    host = url |> URI.parse() |> Map.get(:host)

    if Enum.member?(@electric_peers, host) do
      {:ok, %Req.Response{status: 200, headers: %{"electric-handle" => ["test-handle"]}}}
    else
      {:error, %Req.TransportError{reason: :timeout}}
    end
  end
end
