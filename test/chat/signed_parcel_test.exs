defmodule ChatTest.SignedParcelTest do
  use ExUnit.Case, async: true

  alias Chat.SignedParcel
  alias Chat.Messages
  alias Chat.User
  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Identity

  test "text message parcel is corect" do
    {alice, _bob, dialog} = create_alice_bob_dialog()

    parcel =
      Messages.Text.new("Hello", 1159)
      |> SignedParcel.wrap_dialog_message(dialog, alice)

    refute parcel.data == []
    assert SignedParcel.sign_valid?(parcel, alice.public_key)

    assert [
             {{:dialog_message, _, :next, _}, %Chat.Dialogs.Message{type: :text}}
           ] = parcel.data
  end

  test "memo message parcel is corect" do
    {alice, _bob, dialog} = create_alice_bob_dialog()

    parcel =
      Messages.Text.new(String.pad_trailing("Hello memo", 200, "-"), 1159)
      |> SignedParcel.wrap_dialog_message(dialog, alice)

    refute parcel.data == []
    assert SignedParcel.sign_valid?(parcel, alice.public_key)

    assert [
             {{:memo, _}, _},
             {{:memo_index, _, _}, true},
             {{:memo_index, _, _}, true},
             {{:dialog_message, _, :next, _}, %Chat.Dialogs.Message{type: :memo}}
           ] = parcel.data
  end

  defp create_alice_bob_dialog do
    alice = User.login("Alice")
    bob = Identity.create("Bob")
    dialog = Dialogs.find_or_open(bob, alice |> Card.from_identity())

    {alice, bob, dialog}
  end
end
