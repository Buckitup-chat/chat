defmodule Chat.Data.DialogKeyTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Dialog
  alias Chat.Data.Integrity
  alias Chat.Data.Integrity.Signable
  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Types.DialogHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    alice = User.generate_pq_identity("Alice")
    bob = User.generate_pq_identity("Bob")
    alice_card = insert_signed_user_card(alice)
    bob_card = insert_signed_user_card(bob)

    dialog_hash = compute_dialog_hash(alice_card.user_hash, bob_card.user_hash)

    {:ok,
     alice: alice,
     bob: bob,
     alice_hash: alice_card.user_hash,
     bob_hash: bob_card.user_hash,
     dialog_hash: dialog_hash}
  end

  describe "valid dialog_key — peer sync" do
    test "is persisted", %{alice: alice, alice_hash: ah, bob_hash: bh, dialog_hash: dh} do
      dk = signed_dialog_key(alice, dh, ah, bh)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk)

      assert Dialog.get_dialog_key(dh, ah) != nil
    end

    test "LWW — newer timestamp overwrites", %{
      alice: alice,
      alice_hash: ah,
      bob_hash: bh,
      dialog_hash: dh
    } do
      dk1 = signed_dialog_key(alice, dh, ah, bh, owner_timestamp: 100)
      dk2 = signed_dialog_key(alice, dh, ah, bh, owner_timestamp: 200)

      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk1)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk2)

      persisted = Dialog.get_dialog_key(dh, ah)
      assert persisted.owner_timestamp == 200
    end

    test "LWW — older timestamp is rejected", %{
      alice: alice,
      alice_hash: ah,
      bob_hash: bh,
      dialog_hash: dh
    } do
      dk1 = signed_dialog_key(alice, dh, ah, bh, owner_timestamp: 200)
      dk2 = signed_dialog_key(alice, dh, ah, bh, owner_timestamp: 100)

      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk1)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk2)

      persisted = Dialog.get_dialog_key(dh, ah)
      assert persisted.owner_timestamp == 200
    end
  end

  describe "tampered dialog_key — peer sync" do
    test "tampered field is not persisted", %{
      alice: alice,
      alice_hash: ah,
      bob_hash: bh,
      dialog_hash: dh
    } do
      dk = signed_dialog_key(alice, dh, ah, bh)
      tampered = %{dk | peer_kem_wrap_key_b64: "tampered"}

      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, tampered)

      assert Dialog.get_dialog_key(dh, ah) == nil
    end

    test "wrong signing key is not persisted", %{
      bob: bob,
      alice_hash: ah,
      bob_hash: bh,
      dialog_hash: dh
    } do
      dk = build_dialog_key(dh, ah, bh) |> sign_with_key(bob.sign_skey)

      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk)

      assert Dialog.get_dialog_key(dh, ah) == nil
    end
  end

  describe "signable protocol" do
    test "signable_fields excludes sign_b64 and __meta__" do
      dk = %DialogKey{
        dialog_hash: "di_" <> String.duplicate("ab", 64),
        sender_hash: "u_" <> String.duplicate("cd", 64),
        peer_hash: "u_" <> String.duplicate("ef", 64),
        peer_kem_wrap_key_b64: "key",
        peer_wrapped_msg_key_b64: "wrapped",
        owner_timestamp: 1,
        deleted_flag: false,
        sign_b64: "sig"
      }

      fields = Signable.signable_fields(dk)
      refute Map.has_key?(fields, :sign_b64)
      refute Map.has_key?(fields, :__meta__)
      assert Map.has_key?(fields, :dialog_hash)
      assert Map.has_key?(fields, :sender_hash)
      assert Map.has_key?(fields, :peer_hash)
    end
  end

  describe "update path — peer sync" do
    test "valid update overwrites existing", %{
      alice: alice,
      alice_hash: ah,
      bob_hash: bh,
      dialog_hash: dh
    } do
      dk1 = signed_dialog_key(alice, dh, ah, bh, owner_timestamp: 100)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk1)

      dk2 = signed_dialog_key(alice, dh, ah, bh, owner_timestamp: 200)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :update, dk2)

      persisted = Dialog.get_dialog_key(dh, ah)
      assert persisted.owner_timestamp == 200
    end

    test "stale update is rejected", %{
      alice: alice,
      alice_hash: ah,
      bob_hash: bh,
      dialog_hash: dh
    } do
      dk1 = signed_dialog_key(alice, dh, ah, bh, owner_timestamp: 200)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk1)

      dk2 = signed_dialog_key(alice, dh, ah, bh, owner_timestamp: 100)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :update, dk2)

      persisted = Dialog.get_dialog_key(dh, ah)
      assert persisted.owner_timestamp == 200
    end

    test "update with invalid signature is rejected", %{
      alice: alice,
      bob: bob,
      alice_hash: ah,
      bob_hash: bh,
      dialog_hash: dh
    } do
      dk1 = signed_dialog_key(alice, dh, ah, bh, owner_timestamp: 100)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk1)

      dk2 = build_dialog_key(dh, ah, bh, owner_timestamp: 200) |> sign_with_key(bob.sign_skey)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :update, dk2)

      persisted = Dialog.get_dialog_key(dh, ah)
      assert persisted.owner_timestamp == 100
    end

    test "update for non-existing key is ignored", %{
      alice: alice,
      alice_hash: ah,
      bob_hash: bh,
      dialog_hash: dh
    } do
      dk = signed_dialog_key(alice, dh, ah, bh)
      {:ok, _} = ShapeWriter.write(:dialog_keys, :update, dk)

      assert Dialog.get_dialog_key(dh, ah) == nil
    end
  end

  # --- Helpers ---

  defp compute_dialog_hash(hash_a, hash_b) do
    sorted = Enum.sort([hash_a, hash_b])
    binary = :crypto.hash(:sha3_512, Enum.join(sorted))
    DialogHash.from_binary(binary)
  end

  defp build_dialog_key(dialog_hash, sender_hash, peer_hash, attrs \\ []) do
    %DialogKey{
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      peer_hash: peer_hash,
      peer_kem_wrap_key_b64: :crypto.strong_rand_bytes(32),
      peer_wrapped_msg_key_b64: :crypto.strong_rand_bytes(44),
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond)),
      deleted_flag: false
    }
  end

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{struct | sign_b64: sign_b64}
  end

  defp signed_dialog_key(identity, dialog_hash, sender_hash, peer_hash, attrs \\ []) do
    build_dialog_key(dialog_hash, sender_hash, peer_hash, attrs)
    |> sign_with_key(identity.sign_skey)
  end

  defp insert_signed_user_card(identity) do
    card = identity |> User.extract_pq_card() |> sign_card(identity.sign_skey)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp sign_card(card, sign_skey) do
    sign_b64 = card |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{card | sign_b64: sign_b64}
  end
end
