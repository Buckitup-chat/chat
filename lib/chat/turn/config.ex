defmodule Chat.Turn.Config do
  @moduledoc "TURN relay configuration and per-boot secret"

  use GenServer

  @secret_size 32
  @default_ttl 600
  @default_rate_per_ip_hour 60
  @turn_port 3478

  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  def secret, do: GenServer.call(__MODULE__, :secret)
  def enabled?, do: GenServer.call(__MODULE__, :enabled?)
  def public_ip, do: GenServer.call(__MODULE__, :public_ip)
  def uris, do: GenServer.call(__MODULE__, :uris)
  def ttl, do: GenServer.call(__MODULE__, :ttl)
  def rate_per_ip_hour, do: GenServer.call(__MODULE__, :rate_per_ip_hour)

  @impl true
  def init(_opts) do
    secret = :crypto.strong_rand_bytes(@secret_size)

    turn_public_ip = System.get_env("TURN_PUBLIC_IP")
    domain = endpoint_domain()
    resolved_ip = resolve_domain(domain)

    public_ip = turn_public_ip || resolved_ip
    enabled = public_ip != nil

    uris = parse_uris(System.get_env("TURN_URIS"), domain, turn_public_ip)

    ttl =
      case System.get_env("TURN_TTL_SECONDS") do
        nil -> @default_ttl
        val -> String.to_integer(val)
      end

    rate =
      case System.get_env("TURN_RATE_PER_IP_HOUR") do
        nil -> @default_rate_per_ip_hour
        val -> String.to_integer(val)
      end

    state = %{
      secret: secret,
      enabled: enabled,
      public_ip: public_ip,
      uris: uris,
      ttl: ttl,
      rate_per_ip_hour: rate
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:secret, _from, state), do: {:reply, state.secret, state}
  def handle_call(:enabled?, _from, state), do: {:reply, state.enabled, state}
  def handle_call(:public_ip, _from, state), do: {:reply, state.public_ip, state}
  def handle_call(:uris, _from, state), do: {:reply, state.uris, state}
  def handle_call(:ttl, _from, state), do: {:reply, state.ttl, state}
  def handle_call(:rate_per_ip_hour, _from, state), do: {:reply, state.rate_per_ip_hour, state}

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
