defmodule ChatTest.SignedParcelTest do
  use ExUnit.Case, async: true
  # import Mock

  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.SignedParcel
  alias Chat.Dialogs.Message, as: DialogMessage
  # alias Chat.Dialogs.Registry, as: DialogRegistry

  test "text message parcel is corect" do
    {alice, bob, dialog} = create_alice_bob_dialog()

    parcel =
      Messages.Text.new("Hello", 1159)
      |> SignedParcel.wrap_dialog_message(dialog, alice)

    refute SignedParcel.data_items(parcel) == []
    assert SignedParcel.scope_valid?(parcel, bob.public_key)
    assert SignedParcel.scope_valid?(parcel, alice.public_key)
    assert SignedParcel.sign_valid?(parcel, alice.public_key)

    assert [
             {{:dialog_message, _, :next, _}, %Chat.Dialogs.Message{type: :text}}
           ] = parcel |> SignedParcel.data_items()

    # Test prepare_for_broadcast for text message
    assert {:new_dialog_message, _, {_, %Chat.Dialogs.Message{type: :text}}} =
             SignedParcel.prepare_for_broadcast(parcel)

    # Test inject_next_index for text message
    injected = SignedParcel.inject_next_index(parcel)
    assert [{{:dialog_message, _, next, _}, _}] = SignedParcel.data_items(injected)
    refute next == :next
  end

  test "memo message parcel is corect" do
    {alice, bob, dialog} = create_alice_bob_dialog()

    parcel =
      Messages.Text.new(String.pad_trailing("Hello memo", 200, "-"), 1159)
      |> SignedParcel.wrap_dialog_message(dialog, alice)

    refute SignedParcel.data_items(parcel) == []
    assert SignedParcel.scope_valid?(parcel, bob.public_key)
    assert SignedParcel.scope_valid?(parcel, alice.public_key)
    assert SignedParcel.sign_valid?(parcel, alice.public_key)

    assert [
             {{:memo, _}, _},
             {{:memo_index, _, _}, true},
             {{:memo_index, _, _}, true},
             {{:dialog_message, _, :next, _}, %Chat.Dialogs.Message{type: :memo}}
           ] = parcel |> SignedParcel.data_items()

    # Test prepare_for_broadcast for memo
    assert {:new_dialog_message, _, {_, %Chat.Dialogs.Message{type: :memo}}} =
             SignedParcel.prepare_for_broadcast(parcel)

    # Test inject_next_index for memo
    injected = SignedParcel.inject_next_index(parcel)
    assert [_, _, _, {{:dialog_message, _, next, _}, _}] = SignedParcel.data_items(injected)
    refute next == :next
  end

  test "room invite message parcel is correct" do
    {alice, bob, dialog} = create_alice_bob_dialog()
    room = Identity.create("Room")

    parcel =
      Messages.RoomInvite.new(room, 1159)
      |> SignedParcel.wrap_dialog_message(dialog, alice)

    refute SignedParcel.data_items(parcel) == []
    assert SignedParcel.scope_valid?(parcel, bob.public_key)
    assert SignedParcel.scope_valid?(parcel, alice.public_key)
    assert SignedParcel.sign_valid?(parcel, alice.public_key)

    assert [
             {{:room_invite, _}, _},
             {{:room_invite_index, _, _}, _},
             {{:room_invite_index, _, _}, _},
             {{:dialog_message, _, :next, _}, %Chat.Dialogs.Message{type: :room_invite}}
           ] = parcel |> SignedParcel.data_items()

    # Test prepare_for_broadcast for room invite
    assert {:new_dialog_message, _, {_, %Chat.Dialogs.Message{type: :room_invite}}} =
             SignedParcel.prepare_for_broadcast(parcel)

    # Test inject_next_index for room invite
    injected = SignedParcel.inject_next_index(parcel)
    assert [_, _, _, {{:dialog_message, _, next, _}, _}] = SignedParcel.data_items(injected)
    refute next == :next
  end

  test "invalid signature is detected" do
    {alice, _bob, dialog} = create_alice_bob_dialog()
    charlie = Identity.create("Charlie")

    parcel =
      Messages.Text.new("Hello", 1159)
      |> SignedParcel.wrap_dialog_message(dialog, alice)

    # Test with wrong public key
    refute SignedParcel.sign_valid?(parcel, charlie.public_key)
  end

  test "invalid scope is detected" do
    {alice, _bob, dialog} = create_alice_bob_dialog()
    charlie = Identity.create("Charlie")

    parcel =
      Messages.Text.new("Hello", 1159)
      |> SignedParcel.wrap_dialog_message(dialog, alice)

    # Test with public key not in dialog
    refute SignedParcel.scope_valid?(parcel, charlie.public_key)
  end

  # test "scope_valid? handles invalid memo keys" do
  #   {alice, _bob, dialog} = create_alice_bob_dialog()
  #   charlie = Identity.create("Charlie")
  #   david = Identity.create("David")

  #   # Create a memo message parcel
  #   parcel =
  #     Messages.Text.new(String.pad_trailing("Hello memo", 200, "-"), 1159)
  #     |> SignedParcel.wrap_dialog_message(dialog, alice)

  #   # Test when neither key matches
  #   refute SignedParcel.scope_valid?(parcel, charlie.public_key)

  #   # Test when keys are not in dialog peers
  #   mock_dialog = %{a_key: alice.public_key, b_key: david.public_key}
  #   with_mock DialogRegistry, [find: fn _ -> mock_dialog end] do
  #     parcel = %SignedParcel{
  #       data: [
  #         {{:memo, "key"}, "data"},
  #         {{:memo_index, charlie.public_key, "key"}, true},
  #         {{:memo_index, david.public_key, "key"}, true},
  #         {{:dialog_message, "dialog_key", :next, "msg_id"}, %DialogMessage{type: :memo}}
  #       ]
  #     }
  #     refute SignedParcel.scope_valid?(parcel, charlie.public_key)
  #   end
  # end

  # test "scope_valid? handles invalid room invite keys" do
  #   {alice, _bob, dialog} = create_alice_bob_dialog()
  #   charlie = Identity.create("Charlie")
  #   david = Identity.create("David")
  #   room = Identity.create("Room")

  #   # Create a room invite message parcel
  #   parcel =
  #     Messages.RoomInvite.new(room, 1159)
  #     |> SignedParcel.wrap_dialog_message(dialog, alice)

  #   # Test when neither key matches
  #   refute SignedParcel.scope_valid?(parcel, charlie.public_key)

  #   # Test when keys are not in dialog peers
  #   mock_dialog = %{a_key: alice.public_key, b_key: david.public_key}
  #   with_mock DialogRegistry, [find: fn _ -> mock_dialog end] do
  #     parcel = %SignedParcel{
  #       data: [
  #         {{:room_invite, "key"}, "data"},
  #         {{:room_invite_index, charlie.public_key, "key"}, true},
  #         {{:room_invite_index, david.public_key, "key"}, true},
  #         {{:dialog_message, "dialog_key", :next, "msg_id"}, %DialogMessage{type: :room_invite}}
  #       ]
  #     }
  #     refute SignedParcel.scope_valid?(parcel, charlie.public_key)
  #   end
  # end

  test "main_item handles unknown message type" do
    parcel = %SignedParcel{
      data: [
        {{:dialog_message, "dialog_key", :next, "msg_id"}, %DialogMessage{type: :unknown}}
      ]
    }

    assert_raise CaseClauseError, fn ->
      SignedParcel.main_item(parcel)
    end
  end

  test "inject_next_index handles unknown message type" do
    parcel = %SignedParcel{
      data: [
        {{:dialog_message, "dialog_key", 1, "msg_id"}, %DialogMessage{type: :unknown}}
      ]
    }

    # Should return input unchanged for unknown types
    assert ^parcel = SignedParcel.inject_next_index(parcel)
  end

  test "Enigma.Hash.Protocol implementation" do
    parcel = %SignedParcel{
      data: [
        {{:dialog_message, "dialog_key", :next, "msg_id"}, %DialogMessage{type: :text}}
      ]
    }

    # Should produce a string representation of the data field
    result = Enigma.Hash.Protocol.to_iodata(parcel)
    assert is_binary(result)
    assert String.contains?(result, "dialog_key")
    assert String.contains?(result, "msg_id")
  end

  # test "wrap_dialog_message handles different data_list entries" do
  #   {alice, _bob, dialog} = create_alice_bob_dialog()
  #   msg = %Messages.Text{text: "test"}
  #   with_mock Chat.DryStorable, [
  #     type: fn _ -> :text end,
  #     timestamp: fn _ -> 0 end,
  #     content: fn _ -> "test" end,
  #     to_parcel: fn _ -> {"test", []} end
  #   ] do
  #     parcel = SignedParcel.wrap_dialog_message(msg, dialog, alice)
  #     assert [{{:dialog_message, _, :next, _}, %DialogMessage{}}] = SignedParcel.data_items(parcel)
  #   end
  # end

  # test "dialog_peer_keys handles missing dialog" do
  #   with_mock DialogRegistry, [find: fn _ -> nil end] do
  #     parcel = %SignedParcel{
  #       data: [
  #         {{:dialog_message, "dialog_key", :next, "msg_id"}, %DialogMessage{type: :text}}
  #       ]
  #     }
  #     assert_raise KeyError, fn ->
  #       SignedParcel.scope_valid?(parcel, "some_key")
  #     end
  #   end
  # end

  defp create_alice_bob_dialog do
    alice = Identity.create("Alice")
    bob = Identity.create("Bob")
    dialog = Dialogs.find_or_open(alice, bob |> Card.from_identity())

    {alice, bob, dialog}
  end
end
