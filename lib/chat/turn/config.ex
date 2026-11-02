defmodule Chat.Turn.Config do
  @moduledoc "TURN relay configuration and per-boot secret"

  @key __MODULE__
  @secret_size 32
  @default_ttl 600
  @default_rate_per_ip_hour 60
  @turn_port 3478

  def setup do
    secret = :crypto.strong_rand_bytes(@secret_size)
    turn_public_ip = System.get_env("TURN_PUBLIC_IP")
    domain = endpoint_domain()
    resolved_ip = resolve_domain(domain)
    public_ip = turn_public_ip || resolved_ip

    :persistent_term.put(@key, %{
      secret: secret,
      enabled: public_ip != nil,
      public_ip: public_ip,
      uris: parse_uris(System.get_env("TURN_URIS"), domain, turn_public_ip),
      ttl: env_int("TURN_TTL_SECONDS", @default_ttl),
      rate_per_ip_hour: env_int("TURN_RATE_PER_IP_HOUR", @default_rate_per_ip_hour)
    })
  end

  def secret, do: get(:secret)
  def enabled?, do: get(:enabled)
  def public_ip, do: get(:public_ip)
  def uris, do: get(:uris)
  def ttl, do: get(:ttl)
  def rate_per_ip_hour, do: get(:rate_per_ip_hour)

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
