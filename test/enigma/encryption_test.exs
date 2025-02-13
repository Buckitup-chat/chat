defmodule Enigma.EncryptionTest do
  use ExUnit.Case, async: true

  describe "plain encryption" do
    test "bob can read alice message" do
      %{}
      |> there_are_alice_and_bob_and_the_message
      |> alice_encrypts_the_message_to_bob
      |> bob_decrypts_the_message_from_alice
      |> assert_decrypted_message_is_the_same
    end

    test "author(alice) can decrypt own message" do
      %{}
      |> there_are_alice_and_bob_and_the_message
      |> alice_encrypts_the_message_to_bob
      |> alice_decrypts_own_message_to_bob
      |> assert_decrypted_message_is_the_same
    end

    test "not involved reader can't decrypt message" do
      %{}
      |> there_are_alice_and_bob_and_the_message
      |> alice_encrypts_the_message_to_bob
      |> there_is_eve
      |> eve_decrypts_the_message_from_alice
      |> refute_decrypted_message_is_the_same
    end
  end

  describe "signed encryption" do
    test "bob can read alice signed message" do
      %{}
      |> there_are_alice_and_bob_and_the_message
      |> alice_encrypt_and_signs_the_message_to_bob
      |> bob_decrypts_signed_message_from_alice
      |> assert_decrypted_message_is_the_same
    end

    test "author(alice) can decrypt own signed message" do
      %{}
      |> there_are_alice_and_bob_and_the_message
      |> alice_encrypt_and_signs_the_message_to_bob
      |> alice_decrypts_signed_own_message
      |> assert_decrypted_message_is_the_same
    end

    test "not involved reader can't decrypt signed message" do
      %{}
      |> there_are_alice_and_bob_and_the_message
      |> alice_encrypt_and_signs_the_message_to_bob
      |> there_is_eve
      |> assert_eve_fails_to_decrypt_signed_message
    end
  end

  describe "bisigned encryption" do
    test "bob can read alice bisigned message sharing room key" do
      %{}
      |> there_are_alice_and_bob_and_room_and_the_message
      |> alice_encrypt_and_bisigns_the_room_message
      |> bob_decrypts_bisigned_room_message_from_alice
      |> assert_decrypted_message_is_the_same
    end

    test "author(alice) can decrypt own bisigned room message " do
      %{}
      |> there_are_alice_and_bob_and_room_and_the_message
      |> alice_encrypt_and_bisigns_the_room_message
      |> alice_decrypts_bisigned_own_room_message
      |> assert_decrypted_message_is_the_same
    end

    test "not involved reader can't decrypt bisigned message without room key" do
      %{}
      |> there_are_alice_and_bob_and_room_and_the_message
      |> alice_encrypt_and_bisigns_the_room_message
      |> there_is_eve
      |> assert_eve_fails_to_decrypt_bisigned_message
    end

    test "not involved reader can verify bisigned message is eligible for the room (room public key is known)" do
      %{}
      |> there_are_alice_and_bob_and_room_and_the_message
      |> alice_encrypt_and_bisigns_the_room_message
      |> there_is_eve
      |> assert_eve_can_verify_bisigned_message_is_for_the_room
    end
  end

  defp there_are_alice_and_bob_and_the_message(context) do
    context
    |> add_person(:alice)
    |> add_person(:bob)
    |> add_message("Some secret message")
  end

  defp there_are_alice_and_bob_and_room_and_the_message(context) do
    context
    |> add_person(:alice)
    |> add_person(:bob)
    |> add_room()
    |> add_message("Some secret message")
  end

  defp there_is_eve(context), do: context |> add_person(:eve)

  defp alice_encrypts_the_message_to_bob(context),
    do: context |> encrypt_message(as: :alice, to: :bob)

  defp alice_decrypts_own_message_to_bob(context),
    do: context |> decrypt_message(as: :alice, from: :bob)

  defp bob_decrypts_the_message_from_alice(context),
    do: context |> decrypt_message(as: :bob, from: :alice)

  defp eve_decrypts_the_message_from_alice(context),
    do: context |> decrypt_message(as: :eve, from: :alice)

  defp assert_decrypted_message_is_the_same(context),
    do: tap(context, &assert(decrypted_is_the_same?(&1)))

  defp refute_decrypted_message_is_the_same(context),
    do: tap(context, &refute(decrypted_is_the_same?(&1)))

  defp alice_encrypt_and_signs_the_message_to_bob(context),
    do: context |> encrypt_and_sign_message(as: :alice, to: :bob)

  defp bob_decrypts_signed_message_from_alice(context) do
    assert {:ok, decrypted} = decrypt_signed(context, as: :bob, to: :alice, from: :alice)
    assert decrypted == context.message
    context |> set_decrypted(decrypted)
  end

  defp alice_decrypts_signed_own_message(context) do
    assert {:ok, decrypted} = decrypt_signed(context, as: :alice, to: :bob, from: :alice)
    assert decrypted == context.message
    context |> set_decrypted(decrypted)
  end

  defp assert_eve_fails_to_decrypt_signed_message(context) do
    tap(context, &assert(:error == decrypt_signed(&1, as: :eve, to: :bob, from: :alice)))
  end

  defp alice_encrypt_and_bisigns_the_room_message(context),
    do: context |> encrypt_and_bisign_message(as: :alice, room: :room)

  defp alice_decrypts_bisigned_own_room_message(context) do
    assert {:ok, decrypted} = decrypt_bisigned_message(context, from: :alice, room: :room)
    assert decrypted == context.message
    context |> set_decrypted(decrypted)
  end

  defp bob_decrypts_bisigned_room_message_from_alice(context) do
    assert {:ok, decrypted} = decrypt_bisigned_message(context, from: :alice, room: :room)
    context |> set_decrypted(decrypted)
  end

  defp assert_eve_fails_to_decrypt_bisigned_message(context) do
    tap(context, fn context ->
      assert :error_out_sign == decrypt_bisigned_message(context, from: :alice, room: :eve)
    end)
  end

  defp assert_eve_can_verify_bisigned_message_is_for_the_room(context) do
    tap(context, fn context ->
      {encrypted_data, _data_sign, encrypted_data_sign} = context.encrypted_and_bisigned
      assert Enigma.valid_sign?(encrypted_data_sign, encrypted_data, context.room.pub_key)
    end)
  end

  defp add_person(context, name), do: context |> Map.put(name, generate_keys())
  defp add_room(context), do: context |> Map.put(:room, generate_keys())
  defp add_message(context, message), do: context |> Map.put(:message, message)
  defp set_decrypted(context, decrypted), do: context |> Map.put(:decrypted, decrypted)
  defp decrypted_is_the_same?(context), do: context.message == context.decrypted

  defp encrypt_message(context, as: as, to: to) do
    Enigma.encrypt(context.message, context[as].priv_key, context[to].pub_key)
    |> then(&Map.put(context, :encrypted, &1))
  end

  defp decrypt_message(context, as: as, from: from) do
    Enigma.decrypt(context.encrypted, context[as].priv_key, context[from].pub_key)
    |> then(&set_decrypted(context, &1))
  end

  defp encrypt_and_sign_message(context, as: as, to: to) do
    Enigma.encrypt_and_sign(context.message, context[as].priv_key, context[to].pub_key)
    |> then(&Map.put(context, :encrypted_and_signed, &1))
  end

  defp decrypt_signed(context, as: as, to: to, from: from) do
    Enigma.decrypt_signed(
      context.encrypted_and_signed,
      context[as].priv_key,
      context[to].pub_key,
      context[from].pub_key
    )
  end

  defp encrypt_and_bisign_message(context, as: as, room: room) do
    Enigma.encrypt_and_bisign(context.message, context[as].priv_key, context[room].priv_key)
    |> then(&Map.put(context, :encrypted_and_bisigned, &1))
  end

  defp decrypt_bisigned_message(context, from: user, room: room) do
    Enigma.decrypt_bisigned(
      context.encrypted_and_bisigned,
      context[room].priv_key,
      context[user].pub_key
    )
  end

  defp generate_keys do
    {priv_key, pub_key} = Enigma.generate_keys()
    %{priv_key: priv_key, pub_key: pub_key}
  end
end
