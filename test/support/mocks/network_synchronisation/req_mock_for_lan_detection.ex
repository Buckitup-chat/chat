defmodule ChatSupport.Mocks.NetworkSynchronization.ReqMockForLanDetection do
  @moduledoc "Mocking Req for LAN Electric peer detection"

  @open_peers ["10.10.10.111", "10.10.10.20"]
  # trust-mode peers answer shape reads with 401 read_session_required
  @gated_peers ["10.10.10.30"]

  def electric_peers_list, do: @open_peers ++ @gated_peers

  def get(url, _opts \\ []) do
    %URI{host: host} = URI.parse(url)

    cond do
      host in @open_peers ->
        {:ok, %Req.Response{status: 200, headers: %{"electric-handle" => ["test-handle"]}}}

      host in @gated_peers ->
        {:ok,
         %Req.Response{
           status: 401,
           body: %{"error" => "read_session_required", "shape" => "user_card"}
         }}

      true ->
        {:error, %Req.TransportError{reason: :timeout}}
    end
  end
end
