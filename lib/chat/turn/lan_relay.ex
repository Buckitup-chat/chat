defmodule Chat.Turn.LanRelay do
  @moduledoc """
  Device relay API: one UDP listener per LAN address.

  Platform drives it from VintageNet events; the credentials endpoint reads
  `active?/1` to decide whether the address a request arrived at has a relay.
  """

  use Toolbox.OriginLog

  alias Chat.Turn.Listener

  @key {__MODULE__, :active}

  @spec start(:inet.ip4_address(), [:inet.ip4_address()], [Chat.Turn.Cidr.subnet()]) ::
          :ok | {:error, term()}
  def start(ip, own_ips, allowed) do
    opts = Listener.opts(ip, own_ips, allowed)

    ip
    |> Listener.add(:udp, opts)
    |> tap(fn
      :ok ->
        put_active(MapSet.put(active(), ip))
        log("relay started on #{:inet.ntoa(ip)}, #{length(allowed)} allowed ranges", :info)

      {:error, reason} ->
        log("relay on #{:inet.ntoa(ip)} failed: #{inspect(reason)}", :warning)
    end)
  end

  @spec stop(:inet.ip4_address()) :: :ok
  def stop(ip) do
    Listener.remove(ip, :udp)
    put_active(MapSet.delete(active(), ip))
    log("relay stopped on #{:inet.ntoa(ip)}", :info)
  end

  @spec active?(:inet.ip_address()) :: boolean()
  def active?(ip), do: MapSet.member?(active(), ip)

  @spec active() :: MapSet.t()
  def active, do: :persistent_term.get(@key, MapSet.new())

  defp put_active(set), do: :persistent_term.put(@key, set)
end
