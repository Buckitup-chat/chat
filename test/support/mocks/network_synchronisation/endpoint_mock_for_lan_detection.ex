defmodule ChatSupport.Mocks.NetworkSynchronization.EndpointMockForLanDetection do
  @moduledoc "Mocking ChatWeb.Endpoint for LAN detection port discovery"

  def config(:http), do: [port: 4444]
end
