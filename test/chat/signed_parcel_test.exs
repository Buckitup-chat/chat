defmodule ChatTest.SignedParcelTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Mesages
  alias Chat.SignedParcel

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
  end

  defp create_alice_bob_dialog do
    alice = Identity.create("Alice")
    bob = Identity.create("Bob")
    dialog = Dialogs.find_or_open(bob, alice |> Card.from_identity())

    {alice, bob, dialog}
  end
end
