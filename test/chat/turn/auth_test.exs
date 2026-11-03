defmodule Chat.Turn.AuthTest do
  use ExUnit.Case, async: false

  alias Chat.Turn.Auth
  alias Chat.Turn.Config

  @test_secret "buckitup-test-secret"
  @test_realm "buckitup.test"
  @test_tag "6f1c2a9d4e8b7a3c0d5e9f1a2b3c4d5e"
  @test_vector_username "1791200000:#{@test_tag}"
  @test_vector_credential "lpJ4fKChsz/b21/Y2LZCo1ST4gc="

  defp setup_config do
    prev_state = :persistent_term.get(Config, nil)

    :persistent_term.put(Config, %{
      secret: @test_secret,
      enabled: true,
      public_ip: "203.0.113.1",
      public_ip_tuple: {203, 0, 113, 1},
      realm: @test_realm,
      uris: [],
      ttl: 600,
      rate_per_ip_hour: 60
    })

    on_exit(fn ->
      if prev_state, do: :persistent_term.put(Config, prev_state)
    end)
  end

  describe "test vector" do
    test "HMAC matches the spec credential" do
      setup_config()
      computed = :crypto.mac(:hmac, :sha, @test_secret, @test_vector_username) |> Base.encode64()
      assert computed == @test_vector_credential
    end

    test "expired test vector is correctly refused" do
      setup_config()
      assert Auth.auth_fun(@test_vector_username, @test_realm) == <<"">>
    end
  end

  describe "accepts valid credential before expiry" do
    test "future expiry returns correct credential" do
      setup_config()
      future = System.os_time(:second) + 600
      username = "#{future}:#{@test_tag}"
      credential = Auth.auth_fun(username, @test_realm)
      expected = :crypto.mac(:hmac, :sha, @test_secret, username) |> Base.encode64()
      assert credential == expected
    end
  end

  describe "refuses after expiry" do
    test "expired credential returns empty binary" do
      setup_config()
      past = System.os_time(:second) - 10
      username = "#{past}:#{@test_tag}"
      assert Auth.auth_fun(username, @test_realm) == <<"">>
    end
  end

  describe "refuses wrong realm" do
    test "different realm returns empty binary" do
      setup_config()
      future = System.os_time(:second) + 600
      username = "#{future}:#{@test_tag}"
      assert Auth.auth_fun(username, "wrong.realm") == <<"">>
    end
  end

  describe "refuses unparseable username" do
    test "no colon returns empty binary" do
      setup_config()
      assert Auth.auth_fun("nocolon", @test_realm) == <<"">>
    end

    test "empty tag returns empty binary" do
      setup_config()
      assert Auth.auth_fun("12345:", @test_realm) == <<"">>
    end

    test "non-integer expiry returns empty binary" do
      setup_config()
      assert Auth.auth_fun("notanumber:sometag", @test_realm) == <<"">>
    end
  end

  describe "never raises" do
    test "nil username" do
      setup_config()
      assert Auth.auth_fun(nil, @test_realm) == <<"">>
    end

    test "nil realm" do
      setup_config()
      assert Auth.auth_fun("123:tag", nil) == <<"">>
    end

    test "integer arguments" do
      setup_config()
      assert Auth.auth_fun(123, 456) == <<"">>
    end

    test "empty binary" do
      setup_config()
      assert Auth.auth_fun(<<>>, <<>>) == <<"">>
    end

    test "binary with only colons" do
      setup_config()
      assert Auth.auth_fun(":::", @test_realm) == <<"">>
    end
  end
end
