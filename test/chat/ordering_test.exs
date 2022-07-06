defmodule Chat.OrderingTest do
  use ExUnit.Case, async: false

  alias Chat.User
  alias Chat.Ordering
  alias Chat.Dialogs
  alias Chat.Card

  test "should provide 1 on new key" do
    assert 1 = Ordering.next({:some, "key"})
  end

  test "should provide next key on existing dialog message" do
    dialog_key_preix = messaged_dialog_key_prefix()

    assert 1 < Ordering.next(dialog_key_preix)
  end

  defp messaged_dialog_key_prefix do
    user = User.login("some")

    dialog = Dialogs.find_or_open(user, user |> Card.from_identity())
    %Chat.Messages.Text{text: "some message"}
    |> Dialogs.add_new_message(user, dialog)

    {:dialog_message, dialog |> Dialogs.Dialog.dialog_key()}
  end
end
