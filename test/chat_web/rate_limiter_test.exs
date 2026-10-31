defmodule ChatWeb.RateLimiterTest do
  use ExUnit.Case, async: true

  alias ChatWeb.RateLimiter

  setup do
    key = {:test, make_ref()}
    {:ok, key: key}
  end

  test "allows requests under the limit", %{key: key} do
    for _ <- 1..5 do
      assert :ok = RateLimiter.check(key, 5, 60_000)
    end
  end

  test "rejects requests over the limit", %{key: key} do
    for _ <- 1..3 do
      assert :ok = RateLimiter.check(key, 3, 60_000)
    end

    assert {:error, retry_after} = RateLimiter.check(key, 3, 60_000)
    assert is_integer(retry_after)
    assert retry_after >= 1
  end

  test "different keys are independent", %{key: key} do
    other_key = {:test, make_ref()}

    for _ <- 1..3 do
      assert :ok = RateLimiter.check(key, 3, 60_000)
    end

    assert {:error, _} = RateLimiter.check(key, 3, 60_000)
    assert :ok = RateLimiter.check(other_key, 3, 60_000)
  end

  test "window expiry allows new requests", %{key: key} do
    for _ <- 1..2 do
      assert :ok = RateLimiter.check(key, 2, 1)
    end

    Process.sleep(5)

    assert :ok = RateLimiter.check(key, 2, 1)
  end
end
