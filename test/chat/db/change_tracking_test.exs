defmodule Chat.Db.ChangeTrackingTest do
  use ExUnit.Case, async: true

  alias Chat.Db.ChangeTracker.Tracking

  test "should add awaits and responces into state" do
    empty = Tracking.new()
    one_await = Tracking.add_await(empty, :some, self(), 1)

    refute one_await == empty

    both = Tracking.add_promise(one_await, :another, {fn -> :ok end, fn -> :exp end}, 1)

    refute both == empty
    refute both == one_await
  end

  test "should respond on found keys" do
    pid = self()

    Tracking.new()
    |> Tracking.add_promise(:to_be_found, {fn -> send(pid, :got_it) end, fn -> :exp end}, 1)
    |> Tracking.extract_keys_found([:to_be_found])

    assert_receive :got_it, 100
  end

  test "should expire and respond" do
    pid = self()

    assert_raise ExUnit.AssertionError,
                 ~r/test should not rely on ChangeTracker expiration/,
                 fn ->
                   Tracking.new()
                   |> Tracking.add_promise(
                     :to_be_found,
                     {fn -> send(pid, :got_it) end, fn -> send(pid, :exp) end},
                     1
                   )
                   |> Tracking.extract_expired(50)
                 end

    assert_receive :exp, 100
  end

  test "should work with multiple actions per key" do
    pid = self()

    Tracking.new()
    |> Tracking.add_promise(:to_be_found, {fn -> send(pid, :got_it) end, fn -> :exp end}, 1)
    |> Tracking.add_promise(:to_be_found, {fn -> send(pid, :got_it_too) end, fn -> :exp end}, 1)
    |> Tracking.extract_keys_found([:to_be_found])

    assert_receive :got_it, 100
    assert_receive :got_it_too, 100
  end
end
