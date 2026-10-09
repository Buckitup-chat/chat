defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.EndpointReqMock do
  @moduledoc "Req stand-in that serves requests in-process from `ChatWeb.Endpoint`."

  def get(url, opts), do: Req.get(url, Keyword.put(opts, :plug, ChatWeb.Endpoint))
  def post(url, opts), do: Req.post(url, Keyword.put(opts, :plug, ChatWeb.Endpoint))
end
