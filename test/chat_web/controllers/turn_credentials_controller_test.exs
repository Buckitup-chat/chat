defmodule ChatWeb.TurnCredentialsControllerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers

  alias Chat.Challenge
  alias Chat.Turn.Config
  alias Chat.Turn.LanRelay
  alias Chat.Turn.RateLimiter

  @path "/electric/v1/turn_credentials"
  @loopback {127, 0, 0, 1}

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)
    :ets.delete_all_objects(RateLimiter)

    {alice, alice_card} = identity_with_card("Alice")

    %{alice: alice, alice_card: alice_card}
  end

  describe "with TURN enabled" do
    setup do
      enable_turn()
      put_gate(:open)
    end

    test "valid PoP returns credentials", %{conn: conn, alice: alice, alice_card: card} do
      conn = post_turn_credentials(conn, card.user_hash, alice.sign_skey)

      assert %{
               "username" => username,
               "credential" => credential,
               "ttl" => ttl,
               "uris" => uris
             } = json_response(conn, 200)

      assert is_binary(username)
      [_expiry, tag] = String.split(username, ":", parts: 2)
      assert tag =~ ~r/\A[0-9a-f]{32}\z/

      assert is_binary(credential)
      assert is_integer(ttl)
      assert is_list(uris)
    end

    test "invalid challenge returns 401", %{conn: conn, alice_card: card} do
      conn =
        post(conn, @path, %{user_hash: card.user_hash, challenge_id: "bogus", signature: "x"})

      assert %{"error" => "Invalid or expired challenge"} = json_response(conn, 401)
    end

    test "unknown user returns 401", %{conn: conn, alice: alice} do
      stranger = Chat.Data.User.generate_pq_identity("Stranger")
      stranger_hash = Chat.Data.User.extract_pq_card(stranger).user_hash

      conn = post_turn_credentials(conn, stranger_hash, alice.sign_skey)

      assert %{"error" => "unknown_user"} = json_response(conn, 401)
    end

    test "wrong signature returns 401", %{conn: conn, alice_card: card} do
      other = Chat.Data.User.generate_pq_identity("Other")

      conn = post_turn_credentials(conn, card.user_hash, other.sign_skey)

      assert %{"error" => "invalid_signature"} = json_response(conn, 401)
    end

    test "reused challenge returns 401", %{conn: conn, alice: alice, alice_card: card} do
      {challenge_id, challenge} = Challenge.store()
      signature = challenge |> EnigmaPq.sign(alice.sign_skey) |> Base.encode64(padding: false)
      params = %{user_hash: card.user_hash, challenge_id: challenge_id, signature: signature}

      assert conn |> post(@path, params) |> json_response(200)

      assert %{"error" => "Invalid or expired challenge"} =
               conn |> post(@path, params) |> json_response(401)
    end

    test "deleted card returns 401", %{conn: conn, alice: alice, alice_card: card} do
      Chat.Repo.update_all(
        Ecto.Query.from(c in Chat.Data.Schemas.UserCard, where: c.user_hash == ^card.user_hash),
        set: [deleted_flag: true]
      )

      conn = post_turn_credentials(conn, card.user_hash, alice.sign_skey)

      assert %{"error" => "unknown_user"} = json_response(conn, 401)
    end

    test "not chain-gated even in trust mode with owner", %{
      conn: conn,
      alice: alice,
      alice_card: alice_card
    } do
      {_owner, owner_card} = identity_with_card("Owner")
      put_gate(:trust, owner_card)

      conn = post_turn_credentials(conn, alice_card.user_hash, alice.sign_skey)

      assert %{"username" => _, "credential" => _} = json_response(conn, 200)
    end
  end

  describe "with TURN disabled" do
    test "returns 503 turn_unavailable", %{conn: conn, alice: alice, alice_card: card} do
      refute Config.enabled?()

      conn = post_turn_credentials(conn, card.user_hash, alice.sign_skey)

      assert %{"error" => "turn_unavailable"} = json_response(conn, 503)
    end
  end

  describe "on a device (lan mode)" do
    setup do
      put_lan_mode()
      put_gate(:open)
      :ok = LanRelay.start(@loopback, [@loopback], [])
      on_exit(fn -> LanRelay.stop(@loopback) end)
    end

    test "without TURN_* env the only URI is the relay at the arrival address", ctx do
      assert System.get_env("TURN_PUBLIC_IP") == nil

      conn = post_turn_credentials(ctx.conn, ctx.alice_card.user_hash, ctx.alice.sign_skey)

      assert %{"uris" => ["turn:127.0.0.1:3478?transport=udp"], "credential" => _} =
               json_response(conn, 200)
    end

    test "address without a relay returns 503", ctx do
      conn =
        ctx.conn
        |> arrived_at({192, 168, 25, 1})
        |> post_turn_credentials(ctx.alice_card.user_hash, ctx.alice.sign_skey)

      assert %{"error" => "turn_unavailable"} = json_response(conn, 503)
    end

    test "per-address rate limit holds", ctx do
      for _ <- 1..Config.rate_per_ip_hour() do
        RateLimiter.check_and_increment({127, 0, 0, 1})
      end

      conn = post_turn_credentials(ctx.conn, ctx.alice_card.user_hash, ctx.alice.sign_skey)

      assert %{"error" => "rate_limited"} = json_response(conn, 429)
    end
  end

  describe "CORS" do
    setup do
      enable_turn()
      put_gate(:open)
    end

    test "OPTIONS returns 204", %{conn: conn} do
      conn = cors_preflight(conn, @path)
      assert conn.status == 204
    end
  end

  defp post_turn_credentials(conn, user_hash, sign_skey) do
    {challenge_id, challenge} = Challenge.store()
    signature = challenge |> EnigmaPq.sign(sign_skey) |> Base.encode64(padding: false)

    post(conn, @path, %{
      user_hash: user_hash,
      challenge_id: challenge_id,
      signature: signature
    })
  end

  defp enable_turn do
    prev_state = :persistent_term.get(Config, nil)
    prev_ip = System.get_env("TURN_PUBLIC_IP")

    System.put_env("TURN_PUBLIC_IP", "203.0.113.1")
    Config.setup()

    on_exit(fn ->
      if prev_ip,
        do: System.put_env("TURN_PUBLIC_IP", prev_ip),
        else: System.delete_env("TURN_PUBLIC_IP")

      if prev_state, do: :persistent_term.put(Config, prev_state), else: Config.setup()
    end)
  end

  defp put_lan_mode do
    prev_state = :persistent_term.get(Config, nil)
    Config.setup(:lan)

    on_exit(fn ->
      if prev_state, do: :persistent_term.put(Config, prev_state), else: Config.setup()
    end)
  end

  defp arrived_at(%{adapter: {adapter, payload}} = conn, local_ip) do
    %{conn | adapter: {adapter, %{payload | sock_data: %{address: local_ip, port: 4444}}}}
  end

  defp cors_preflight(conn, path) do
    conn
    |> put_req_header("access-control-request-method", "POST")
    |> put_req_header("origin", "http://localhost:5173")
    |> Phoenix.ConnTest.options(path)
  end
end
