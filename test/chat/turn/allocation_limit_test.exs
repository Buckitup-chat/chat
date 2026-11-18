defmodule Chat.Turn.AllocationLimitTest do
  use ExUnit.Case, async: false

  import Support.RetryHelper

  alias Chat.Turn.AllocationTracker
  alias Chat.Turn.Config
  alias Chat.Turn.Credentials
  alias Chat.Turn.Listener

  require Record

  Record.defrecordp(:stun, Record.extract(:stun, from_lib: "stun/include/stun.hrl"))

  @ip {127, 0, 0, 1}
  @allocate 0x003
  @refresh 0x004
  @no_reply_ms 300

  setup do
    port = free_udp_port()
    :ok = :stun_listener.add_listener(@ip, port, :udp, Listener.opts(@ip, [@ip]))

    on_exit(fn ->
      :stun_listener.del_listener(@ip, port, :udp)
      stop_all_allocations()
    end)

    %{server: {@ip, port}}
  end

  test "a credential cannot hold more than the per-user limit", %{server: server} do
    credential = Credentials.issue()
    max = AllocationTracker.max_per_user()

    clients = for _ <- 1..max, do: allocate!(server, credential)

    assert {:error, {401, _}} = server |> open_client(credential) |> allocate()
    assert AllocationTracker.count({:user, username(credential)}) == max
    assert {:ok, _} = clients |> hd() |> refresh(600)
  end

  test "concurrent allocations do not race past the per-user limit", %{server: server} do
    credential = Credentials.issue()
    max = AllocationTracker.max_per_user()

    results =
      1..(max * 2)
      |> Enum.map(fn _ -> open_client(server, credential) end)
      |> Task.async_stream(&allocate/1, timeout: 5_000)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) <= max
    retry_until(1_000, fn -> assert user_count(credential) == max end)
  end

  test "releasing an allocation frees its slot", %{server: server} do
    credential = Credentials.issue()
    max = AllocationTracker.max_per_user()

    [released | _] = for _ <- 1..max, do: allocate!(server, credential)
    assert {:ok, _} = refresh(released, 0)

    retry_until(1_000, fn -> assert user_count(credential) == max - 1 end)
    assert {:ok, _} = server |> open_client(credential) |> allocate()
  end

  test "a client IP cannot hold more than the per-IP limit", %{server: server} do
    max = AllocationTracker.max_per_ip()
    credentials = for _ <- 0..div(max, AllocationTracker.max_per_user()), do: Credentials.issue()

    results =
      for credential <- credentials, _ <- 1..AllocationTracker.max_per_user() do
        server |> open_client(credential) |> allocate()
      end

    assert Enum.count(results, &match?({:ok, _}, &1)) == max
    retry_until(1_000, fn -> assert AllocationTracker.count({:ip, @ip}) == max end)
  end

  # Client

  defp allocate!(server, credential) do
    client = server |> open_client(credential) |> fetch_nonce()
    {:ok, _} = request_allocation(client)
    client
  end

  defp allocate(client), do: client |> fetch_nonce() |> request_allocation()

  defp open_client(server, credential) do
    {:ok, sock} = :gen_udp.open(0, [:binary, active: false, ip: @ip])
    %{sock: sock, server: server, credential: credential, nonce: nil}
  end

  defp fetch_nonce(client) do
    challenge = send_request(client, stun(method: @allocate, "REQUESTED-TRANSPORT": :udp))
    %{client | nonce: stun(challenge, :NONCE)}
  end

  defp request_allocation(client) do
    client
    |> authed(stun(method: @allocate, "REQUESTED-TRANSPORT": :udp))
    |> result()
  end

  defp refresh(client, lifetime) do
    client
    |> authed(stun(method: @refresh, LIFETIME: lifetime))
    |> result()
  end

  defp authed(%{credential: {user, pass, _ttl}, nonce: nonce} = client, msg) do
    realm = Config.realm()
    msg = stun(msg, USERNAME: user, REALM: realm, NONCE: nonce)
    send_request(client, msg, {user, realm, pass})
  end

  defp send_request(%{sock: sock, server: {ip, port}}, msg, key \\ :undefined) do
    msg = stun(msg, trid: :binary.decode_unsigned(:crypto.strong_rand_bytes(12)))
    :ok = :gen_udp.send(sock, ip, port, :stun_codec.encode(msg, key))

    case :gen_udp.recv(sock, 0, @no_reply_ms) do
      {:ok, {_ip, _port, packet}} -> packet |> :stun_codec.decode(:datagram) |> elem(1)
      {:error, :timeout} -> :no_reply
    end
  end

  defp result(:no_reply), do: {:error, :no_reply}
  defp result(stun(class: :response) = msg), do: {:ok, msg}
  defp result(stun(class: :error) = msg), do: {:error, stun(msg, :"ERROR-CODE")}

  # Helpers

  defp username({user, _pass, _ttl}), do: user
  defp user_count(credential), do: AllocationTracker.count({:user, username(credential)})

  defp free_udp_port do
    {:ok, sock} = :gen_udp.open(0, ip: @ip)
    {:ok, port} = :inet.port(sock)
    :gen_udp.close(sock)
    port
  end

  defp stop_all_allocations do
    :turn_allocs |> :ets.tab2list() |> Enum.each(fn {_addr, pid} -> :turn.stop(pid) end)
    retry_until(1_000, fn -> assert AllocationTracker.count({:ip, @ip}) == 0 end)
  end
end
