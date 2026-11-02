defmodule Chat.Turn.ConfigTest do
  use ExUnit.Case, async: false

  alias Chat.Turn.Config

  defp start_config(env_vars) do
    prev =
      Enum.map(env_vars, fn {key, val} ->
        prev = System.get_env(key)
        System.put_env(key, val)
        {key, prev}
      end)

    {:ok, pid} = Config.start_link(name: :"turn_config_#{:erlang.unique_integer([:positive])}")

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)

      Enum.each(prev, fn
        {key, nil} -> System.delete_env(key)
        {key, val} -> System.put_env(key, val)
      end)
    end)

    pid
  end

  describe "defaults (no TURN env vars, test env)" do
    test "enabled? returns false when no TURN_PUBLIC_IP and domain is localhost" do
      refute Config.enabled?()
    end

    test "secret returns 32 bytes, stable within one boot" do
      secret = Config.secret()
      assert byte_size(secret) == 32
      assert Config.secret() == secret
    end

    test "ttl defaults to 600" do
      assert Config.ttl() == 600
    end

    test "rate_per_ip_hour defaults to 60" do
      assert Config.rate_per_ip_hour() == 60
    end
  end

  describe "with TURN_PUBLIC_IP" do
    test "enabled? returns true" do
      pid = start_config([{"TURN_PUBLIC_IP", "203.0.113.1"}])
      assert GenServer.call(pid, :enabled?)
    end

    test "public_ip returns the override" do
      pid = start_config([{"TURN_PUBLIC_IP", "203.0.113.1"}])
      assert GenServer.call(pid, :public_ip) == "203.0.113.1"
    end

    test "uris returns two default URIs with the IP" do
      pid = start_config([{"TURN_PUBLIC_IP", "203.0.113.1"}])
      uris = GenServer.call(pid, :uris)

      assert uris == [
               "turn:203.0.113.1:3478?transport=udp",
               "turn:203.0.113.1:3478?transport=tcp"
             ]
    end

    test "secret is 32 bytes and differs from the global instance" do
      pid = start_config([{"TURN_PUBLIC_IP", "203.0.113.1"}])
      secret = GenServer.call(pid, :secret)
      assert byte_size(secret) == 32
      assert secret != Config.secret()
    end
  end

  describe "with custom TURN_URIS" do
    test "uris returns the parsed list" do
      pid =
        start_config([
          {"TURN_PUBLIC_IP", "203.0.113.1"},
          {"TURN_URIS",
           "turn:relay.example.com:3478?transport=udp, turn:relay.example.com:3478?transport=tcp"}
        ])

      uris = GenServer.call(pid, :uris)

      assert uris == [
               "turn:relay.example.com:3478?transport=udp",
               "turn:relay.example.com:3478?transport=tcp"
             ]
    end
  end

  describe "with custom TTL and rate" do
    test "ttl returns custom value" do
      pid = start_config([{"TURN_PUBLIC_IP", "203.0.113.1"}, {"TURN_TTL_SECONDS", "300"}])
      assert GenServer.call(pid, :ttl) == 300
    end

    test "rate_per_ip_hour returns custom value" do
      pid = start_config([{"TURN_PUBLIC_IP", "203.0.113.1"}, {"TURN_RATE_PER_IP_HOUR", "120"}])
      assert GenServer.call(pid, :rate_per_ip_hour) == 120
    end
  end
end
