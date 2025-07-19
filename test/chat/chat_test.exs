defmodule Chat.ChatTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.SignedParcel
  alias Chat.User

  describe "run_when_parcel_stored/2" do
    test "starts task and runs callback when parcel is stored" do
      {alice, _bob, _bob_card, dialog} = setup_alice_bob_dialog()

      text_message = "Hello from Alice to Bob"
      message = %Messages.Text{text: text_message}

      parcel =
        message
        |> SignedParcel.wrap_dialog_message(dialog, alice)
        |> Chat.store_parcel()

      test_pid = self()
      callback_executed = make_ref()

      result =
        Chat.run_when_parcel_stored(parcel, fn received_parcel ->
          send(test_pid, {callback_executed, received_parcel})
        end)

      assert result == parcel
      assert_receive {^callback_executed, ^parcel}, 1000
    end

    test "handles parcels with multiple data items" do
      {alice, _bob, _bob_card, dialog} = setup_alice_bob_dialog()

      long_text = String.duplicate("This is a long memo message. ", 100)
      memo_message = %Messages.Text{text: long_text}

      parcel =
        memo_message
        |> SignedParcel.wrap_dialog_message(dialog, alice)
        |> Chat.store_parcel()

      assert length(parcel.data) > 1

      test_pid = self()
      callback_executed = make_ref()

      result =
        Chat.run_when_parcel_stored(parcel, fn received_parcel ->
          send(test_pid, {callback_executed, received_parcel})
        end)

      assert result == parcel
      assert_receive {^callback_executed, ^parcel}, 5000
    end

    test "validates function arity" do
      {alice, _bob, _bob_card, dialog} = setup_alice_bob_dialog()

      message = %Messages.Text{text: "test"}
      parcel = message |> SignedParcel.wrap_dialog_message(dialog, alice) |> Chat.store_parcel()

      assert_raise FunctionClauseError, fn ->
        Chat.run_when_parcel_stored(parcel, fn -> :wrong_arity end)
      end

      assert_raise FunctionClauseError, fn ->
        Chat.run_when_parcel_stored(parcel, fn _a, _b -> :wrong_arity end)
      end
    end
  end

  defp setup_alice_bob_dialog do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()
    dialog = alice |> Dialogs.open(bob_card)
    {alice, bob, bob_card, dialog}
  end
end
