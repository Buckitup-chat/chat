defmodule Chat.Turn.Listener do
  @moduledoc "Single place for stun listener options and add/remove calls"

  alias Chat.Turn.Auth
  alias Chat.Turn.Config
  alias Chat.Turn.PeerPolicy

  @turn_port 3478
  @relay_min_port 49_152
  @relay_max_port 65_535
  @max_allocations 4
  @max_permissions 16

  def port, do: @turn_port

  @doc """
  Options for a listener relaying from `relay_ip`. Peers in the base
  blacklist and `own_ips` are refused unless covered by `allowed`.
  """
  @spec opts(:inet.ip4_address() | nil, [:inet.ip4_address()], [PeerPolicy.subnet()]) ::
          keyword()
  def opts(relay_ip, own_ips, allowed \\ []) do
    [
      use_turn: true,
      auth_type: :user,
      auth_realm: Config.realm(),
      auth_fun: &Auth.auth_fun/2,
      turn_ipv4_address: relay_ip,
      turn_min_port: @relay_min_port,
      turn_max_port: @relay_max_port,
      turn_max_allocations: @max_allocations,
      turn_max_permissions: @max_permissions
    ] ++ PeerPolicy.listener_opts(own_ips, allowed)
  end

  @doc "Starts a listener; replaces one already bound to the same ip/transport"
  @spec add(:inet.ip4_address(), :udp | :tcp, keyword()) :: :ok | {:error, term()}
  def add(ip, transport, opts) do
    case :stun_listener.add_listener(ip, @turn_port, transport, opts) do
      {:error, :already_started} ->
        remove(ip, transport)
        :stun_listener.add_listener(ip, @turn_port, transport, opts)

      result ->
        result
    end
  end

  @spec remove(:inet.ip4_address(), :udp | :tcp) :: :ok
  def remove(ip, transport) do
    case :stun_listener.del_listener(ip, @turn_port, transport) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end
end
