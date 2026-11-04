defmodule Chat.Turn.Config do
  @moduledoc "TURN relay configuration and per-boot secret"

  @key __MODULE__
  @secret_size 32
  @default_ttl 600
  @default_rate_per_ip_hour 60
  @turn_port 3478

  @doc """
  Puts the per-boot config. `:server` relays on a public IP from TURN_* env or
  the endpoint domain; `:lan` (device) relays on LAN addresses driven by
  platform via `Chat.Turn.LanRelay`, ignoring TURN_* env and domain lookup.
  """
  def setup(mode \\ default_mode()) do
    domain = endpoint_domain()

    %{
      mode: mode,
      secret: :crypto.strong_rand_bytes(@secret_size),
      realm: domain || "buckitup.local",
      ttl: env_int("TURN_TTL_SECONDS", @default_ttl),
      rate_per_ip_hour: env_int("TURN_RATE_PER_IP_HOUR", @default_rate_per_ip_hour)
    }
    |> Map.merge(relay_config(mode, domain))
    |> then(&:persistent_term.put(@key, &1))
  end

  defp relay_config(:lan, _domain) do
    %{enabled: false, public_ip: nil, public_ip_tuple: nil, uris: []}
  end

  defp relay_config(:server, domain) do
    turn_public_ip = System.get_env("TURN_PUBLIC_IP")
    public_ip = turn_public_ip || resolve_domain(domain)

    %{
      enabled: public_ip != nil,
      public_ip: public_ip,
      public_ip_tuple: parse_ip_tuple(public_ip),
      uris: parse_uris(System.get_env("TURN_URIS"), domain, turn_public_ip)
    }
  end

  # coveralls-ignore-start
  if Mix.target() == :host do
    defp default_mode, do: :server
  else
    defp default_mode, do: :lan
  end

  # coveralls-ignore-stop

  def mode, do: get(:mode)

  def secret, do: get(:secret)
  def enabled?, do: get(:enabled)
  def public_ip, do: get(:public_ip)
  def public_ip_tuple, do: get(:public_ip_tuple)
  def realm, do: get(:realm)
  def uris, do: get(:uris)
  def ttl, do: get(:ttl)
  def rate_per_ip_hour, do: get(:rate_per_ip_hour)

  @doc "The only URI of a device relay listening on `ip`"
  def lan_uri(ip), do: "turn:#{:inet.ntoa(ip)}:#{@turn_port}?transport=udp"

  defp get(key), do: :persistent_term.get(@key)[key]

  defp env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      val -> String.to_integer(val)
    end
  end

  defp endpoint_domain do
    case Application.get_env(:chat, ChatWeb.Endpoint)[:url][:host] do
      host when is_binary(host) and host not in ["localhost", ""] -> host
      _ -> nil
    end
  end

  defp resolve_domain(nil), do: nil

  defp resolve_domain(domain) do
    case :inet.getaddr(String.to_charlist(domain), :inet) do
      {:ok, ip} -> ip |> :inet.ntoa() |> to_string()
      _ -> nil
    end
  end

  defp parse_ip_tuple(nil), do: nil

  defp parse_ip_tuple(ip_string) do
    {:ok, tuple} = ip_string |> String.to_charlist() |> :inet.parse_address()
    tuple
  end

  defp parse_uris(nil, domain, turn_public_ip) do
    host = domain || turn_public_ip

    case host do
      nil ->
        []

      _ ->
        [
          "turn:#{host}:#{@turn_port}?transport=udp",
          "turn:#{host}:#{@turn_port}?transport=tcp"
        ]
    end
  end

  defp parse_uris(uris_str, _domain, _turn_public_ip) do
    uris_str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end
end
