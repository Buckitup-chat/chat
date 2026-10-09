defmodule ChatWeb.ReadSessionControllerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers

  alias Chat.Challenge
  alias Chat.Data.User
  alias Chat.Pq.ReadSession

  @read_session_path "/electric/v1/read_session"

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    {owner, owner_card} = identity_with_card("Owner")
    {alice, alice_card} = identity_with_card("Alice")

    %{owner: owner, owner_card: owner_card, alice: alice, alice_card: alice_card}
  end

  describe "without an owner" do
    setup do: put_gate(:trust)

    test "any known user gets a session", %{conn: conn, alice: alice, alice_card: card} do
      conn = post_read_session(conn, card.user_hash, "dialog_messages", alice.sign_skey)

      assert %{"token" => token, "shape" => "dialog_messages", "expires_in" => 300} =
               json_response(conn, 200)

      assert {:ok, %{user_hash: user_hash, shape: :dialog_messages}} = ReadSession.lookup(token)
      assert user_hash == card.user_hash
    end
  end

  describe "with an owner" do
    setup %{owner_card: owner_card} do
      put_gate(:trust, owner_card)
    end

    test "owner always gets a session", %{conn: conn, owner: owner, owner_card: card} do
      conn = post_read_session(conn, card.user_hash, "vouch_token", owner.sign_skey)

      assert %{"shape" => "vouch_token"} = json_response(conn, 200)
    end

    test "user vouched for storage.read gets any shape", ctx do
      vouch_alice_by_owner(ctx, "storage.read")

      for shape <- ["dialog_messages", "file", "user_card"] do
        assert %{"shape" => ^shape} = ctx |> alice_requests(shape) |> json_response(200)
      end
    end

    test "per-shape vouch covers only that shape", ctx do
      vouch_alice_by_owner(ctx, "storage.read.file")

      assert ctx |> alice_requests("file") |> json_response(200)

      assert %{"error" => "not_in_trust_chain", "max_depth" => 7} =
               ctx |> alice_requests("dialog_messages") |> json_response(403)
    end

    test "write vouch does not grant reads", ctx do
      vouch_alice_by_owner(ctx, "storage.write")

      assert %{"error" => "not_in_trust_chain"} =
               ctx |> alice_requests("file") |> json_response(403)
    end

    test "unvouched user is rejected", ctx do
      assert %{"error" => "not_in_trust_chain", "max_depth" => 7} =
               ctx |> alice_requests("user_card") |> json_response(403)
    end
  end

  defp vouch_alice_by_owner(ctx, scope_suffix),
    do: vouch(ctx.owner, ctx.owner_card.user_hash, ctx.alice_card.user_hash, scope_suffix)

  defp alice_requests(ctx, shape),
    do: post_read_session(ctx.conn, ctx.alice_card.user_hash, shape, ctx.alice.sign_skey)

  describe "request errors" do
    setup do: put_gate(:open)

    test "unknown shape", %{conn: conn, alice: alice, alice_card: card} do
      conn = post_read_session(conn, card.user_hash, "no_such_shape", alice.sign_skey)

      assert %{"error" => "unknown_shape"} = json_response(conn, 400)
    end

    test "missing params", %{conn: conn} do
      conn = post(conn, @read_session_path, %{})

      assert %{"error" => "unknown_shape"} = json_response(conn, 400)
    end

    test "reused challenge", %{conn: conn, alice: alice, alice_card: card} do
      {challenge_id, challenge} = Challenge.store()
      signature = challenge |> EnigmaPq.sign(alice.sign_skey) |> Base.encode64(padding: false)

      params = file_session_params(card.user_hash, challenge_id, signature)

      assert conn |> post(@read_session_path, params) |> json_response(200)

      assert %{"error" => "Invalid or expired challenge"} =
               conn |> post(@read_session_path, params) |> json_response(401)
    end

    test "user without a card", %{conn: conn, alice: alice} do
      stranger = User.generate_pq_identity("Stranger")
      stranger_hash = User.extract_pq_card(stranger).user_hash

      conn = post_read_session(conn, stranger_hash, "file", alice.sign_skey)

      assert %{"error" => "unknown_user"} = json_response(conn, 401)
    end

    test "malformed user hash", %{conn: conn, alice: alice} do
      conn = post_read_session(conn, "not-a-hash", "file", alice.sign_skey)

      assert %{"error" => "unknown_user"} = json_response(conn, 401)
    end

    test "signature by another key", %{conn: conn, owner: owner, alice_card: card} do
      conn = post_read_session(conn, card.user_hash, "file", owner.sign_skey)

      assert %{"error" => "invalid_signature"} = json_response(conn, 401)
    end

    test "garbage signature", %{conn: conn, alice_card: card} do
      {challenge_id, _challenge} = Challenge.store()

      params = file_session_params(card.user_hash, challenge_id, "!!not-base64")

      assert %{"error" => "invalid_signature"} =
               conn |> post(@read_session_path, params) |> json_response(401)
    end
  end

  defp file_session_params(user_hash, challenge_id, signature),
    do: %{user_hash: user_hash, shape: "file", challenge_id: challenge_id, signature: signature}
end
