defmodule Chat.Upload.IngestThrottleTest do
  use ExUnit.Case, async: true

  alias Chat.Upload.IngestThrottle

  defp start_throttle(limit) do
    name = :"throttle_#{System.unique_integer([:positive])}"
    start_supervised!({IngestThrottle, name: name, limit: limit, retry_after_seconds: 3})
    name
  end

  test "grants tokens up to the limit, then reports busy with retry_after" do
    throttle = start_throttle(2)

    # Hold both tokens from separate processes so they stay checked out.
    hold_token(throttle)
    hold_token(throttle)

    assert IngestThrottle.in_use(throttle) == 2
    assert {:busy, 3} = IngestThrottle.checkout(throttle)
  end

  test "checkin releases a token" do
    throttle = start_throttle(1)

    assert :ok = IngestThrottle.checkout(throttle)
    assert {:busy, _} = checkout_from_another_process(throttle)

    :ok = IngestThrottle.checkin(throttle)
    # checkin is a cast; wait for it to be processed.
    _ = IngestThrottle.in_use(throttle)

    assert :ok = checkout_from_another_process(throttle)
  end

  test "checkout is idempotent for the same process — no double counting" do
    throttle = start_throttle(1)

    assert :ok = IngestThrottle.checkout(throttle)
    assert :ok = IngestThrottle.checkout(throttle)
    assert IngestThrottle.in_use(throttle) == 1
  end

  test "a token is released automatically when its holder process dies" do
    throttle = start_throttle(1)

    {pid, ref} =
      spawn_monitor(fn ->
        :ok = IngestThrottle.checkout(throttle)

        receive do
          :stop -> :ok
        end
      end)

    # Let the spawned process check out.
    wait_until(fn -> IngestThrottle.in_use(throttle) == 1 end)
    assert {:busy, _} = IngestThrottle.checkout(throttle)

    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}

    # The monitor in the throttle fires and frees the token.
    wait_until(fn -> IngestThrottle.in_use(throttle) == 0 end)
    assert :ok = IngestThrottle.checkout(throttle)
  end

  # Holds a token from a throwaway process that never checks back in.
  defp hold_token(throttle) do
    test = self()

    spawn(fn ->
      :ok = IngestThrottle.checkout(throttle)
      send(test, :held)
      Process.sleep(:infinity)
    end)

    assert_receive :held
  end

  defp checkout_from_another_process(throttle) do
    test = self()
    spawn(fn -> send(test, {:result, IngestThrottle.checkout(throttle)}) end)
    assert_receive {:result, result}
    result
  end

  defp wait_until(fun, attempts \\ 100) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("condition not met in time")
      true -> Process.sleep(10) && wait_until(fun, attempts - 1)
    end
  end
end
