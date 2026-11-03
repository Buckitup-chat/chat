defmodule Chat.Turn.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Chat.Turn.Config
  alias Chat.Turn.RateLimiter

  @test_ip {192, 168, 1, 100}
  @other_ip {10, 0, 0, 1}
  @limit 60

  setup do
    prev = :persistent_term.get(Config, nil)

    :persistent_term.put(Config, %{
      secret: "test-secret",
      enabled: true,
      public_ip: "203.0.113.1",
      public_ip_tuple: {203, 0, 113, 1},
      realm: "test.local",
      uris: [],
      ttl: 600,
      rate_per_ip_hour: @limit
    })

    start_supervised!(RateLimiter)

    on_exit(fn ->
      if prev, do: :persistent_term.put(Config, prev), else: :persistent_term.erase(Config)
    end)

    :ok
  end

  test "allows requests under the limit" do
    assert :ok = RateLimiter.check_and_increment(@test_ip)
  end

  test "60 issues from one IP succeed" do
    for _ <- 1..@limit, do: assert(:ok = RateLimiter.check_and_increment(@test_ip))
  end

  test "the 61st returns error with retry_after" do
    for _ <- 1..@limit, do: RateLimiter.check_and_increment(@test_ip)

    assert {:error, retry_after} = RateLimiter.check_and_increment(@test_ip)
    assert is_integer(retry_after)
    assert retry_after > 0
  end

  test "a different IP is unaffected" do
    for _ <- 1..@limit, do: RateLimiter.check_and_increment(@test_ip)

    assert :ok = RateLimiter.check_and_increment(@other_ip)
  end

  test "expired entries are swept" do
    table = RateLimiter
    cutoff = System.os_time(:second) - 3601
    :ets.insert(table, {@test_ip, cutoff})

    send(Process.whereis(RateLimiter), :sweep)
    Process.sleep(50)

    assert :ets.select_count(table, [{{@test_ip, :_}, [], [true]}]) == 0
  end
end
