defmodule ChatSupport.Mocks.NetworkSynchronization.NeuronMockForLanDetection do
  def new_peers_list, do: ["10.10.10.111", "10.10.10.20", "10.10.10.253"]

  def query(_, _, url: url, connection_opts: _) do
    cond do
      Enum.member?(new_peers_list(), URI.parse(url).host) ->
        {:ok, %Neuron.Response{status_code: 200, body: url}}

      URI.parse(url).host == "10.10.10.100" ->
        Process.exit(self(), :normal)

      true ->
        {:error, :timeout}
    end
  end
end
