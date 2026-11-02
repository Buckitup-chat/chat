defmodule Chat.Pq.ReadGateTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers

  alias Chat.Challenge
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.User
  alias Chat.Pq.ReadGate

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)
    put_gate(:open)

    {alice, alice_card} = identity_with_card("Alice")

    %{alice: alice, alice_card: alice_card}
  end

  describe "verify_user/3" do
    test "returns {:ok, sign_pkey} on valid challenge and signature", %{
      alice: alice,
      alice_card: card
    } do
      {challenge_id, challenge} = Challenge.store()
      signature = challenge |> EnigmaPq.sign(alice.sign_skey) |> Base.encode64(padding: false)

      assert {:ok, sign_pkey} = ReadGate.verify_user(card.user_hash, challenge_id, signature)
      assert sign_pkey == card.sign_pkey
    end

    test "returns {:error, :invalid_challenge} for expired/missing challenge", %{
      alice: alice,
      alice_card: card
    } do
      signature = "placeholder" |> EnigmaPq.sign(alice.sign_skey) |> Base.encode64(padding: false)

      assert {:error, :invalid_challenge} =
               ReadGate.verify_user(card.user_hash, "nonexistent-id", signature)
    end

    test "returns {:error, :invalid_challenge} for nil challenge_id", %{
      alice: alice,
      alice_card: card
    } do
      signature = "placeholder" |> EnigmaPq.sign(alice.sign_skey) |> Base.encode64(padding: false)

      assert {:error, :invalid_challenge} = ReadGate.verify_user(card.user_hash, nil, signature)
    end

    test "returns {:error, :unknown_user} for user without a card", %{alice: alice} do
      stranger = User.generate_pq_identity("Stranger")
      stranger_hash = User.extract_pq_card(stranger).user_hash

      {challenge_id, challenge} = Challenge.store()
      signature = challenge |> EnigmaPq.sign(alice.sign_skey) |> Base.encode64(padding: false)

      assert {:error, :unknown_user} =
               ReadGate.verify_user(stranger_hash, challenge_id, signature)
    end

    test "returns {:error, :unknown_user} for deleted card", %{alice: alice, alice_card: card} do
      {:ok, _} =
        User.update_card(
          Ecto.Changeset.change(%UserCard{user_hash: card.user_hash}, deleted_flag: true)
        )

      {challenge_id, challenge} = Challenge.store()
      signature = challenge |> EnigmaPq.sign(alice.sign_skey) |> Base.encode64(padding: false)

      assert {:error, :unknown_user} =
               ReadGate.verify_user(card.user_hash, challenge_id, signature)
    end

    test "returns {:error, :unknown_user} for malformed user_hash", %{alice: alice} do
      {challenge_id, challenge} = Challenge.store()
      signature = challenge |> EnigmaPq.sign(alice.sign_skey) |> Base.encode64(padding: false)

      assert {:error, :unknown_user} =
               ReadGate.verify_user("not-a-hash", challenge_id, signature)
    end

    test "returns {:error, :unknown_user} for nil user_hash" do
      {challenge_id, _challenge} = Challenge.store()

      assert {:error, :unknown_user} = ReadGate.verify_user(nil, challenge_id, "sig")
    end

    test "returns {:error, :invalid_signature} for wrong key", %{
      alice_card: card
    } do
      wrong_identity = User.generate_pq_identity("Wrong")
      {challenge_id, challenge} = Challenge.store()

      signature =
        challenge |> EnigmaPq.sign(wrong_identity.sign_skey) |> Base.encode64(padding: false)

      assert {:error, :invalid_signature} =
               ReadGate.verify_user(card.user_hash, challenge_id, signature)
    end

    test "returns {:error, :invalid_signature} for garbage signature", %{alice_card: card} do
      {challenge_id, _challenge} = Challenge.store()

      assert {:error, :invalid_signature} =
               ReadGate.verify_user(card.user_hash, challenge_id, "!!not-base64")
    end
  end
end
