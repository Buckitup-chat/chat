defmodule ChatSupport.Mocks.NetworkSynchronization.SynchronizationMockForLanDetection do
  @moduledoc "Mocking Synchronization for LAN detection"
  alias Chat.NetworkSynchronization.Source

  def set_known(peers), do: peers |> Enum.map(&host_to_source/1) |> set_sources
  def synchronisation, do: Process.get(:sources) |> Enum.map(&{&1, nil})
  def add_source, do: Source.new(:rand.uniform(1_000_000)) |> add_to_sources()
  def update_source(id, fields), do: Source.new(id) |> struct(fields) |> update_in_sources()
  def start_source(_), do: :ok

  defp set_sources(sources), do: Process.put(:sources, sources)
  defp add_to_sources(source), do: tap(source, &set_sources([&1 | Process.get(:sources, [])]))

  defp host_to_source(host),
    do: %Source{url: "http://#{host}/naive_api", id: :rand.uniform(1_000_000)}

  defp update_in_sources(source),
    do:
      tap(source, fn source ->
        Process.get(:sources, [])
        |> Enum.map(&if(&1.id == source.id, do: source, else: &1))
        |> set_sources
      end)
end
