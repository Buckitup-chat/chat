defmodule Chat.Test.DialogsFixtures do
  @moduledoc "Alice ↔ Bob dialogs and messages for `Chat.Dialogs` (CubDB dialogs) tests."

  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.User
  alias Support.FakeData

  @doc "Logs in Alice and Bob and opens Alice's dialog with Bob: `{alice, bob, bob_card, dialog}`."
  def alice_bob_dialog do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()

    {alice, bob, bob_card, Dialogs.open(alice, bob_card)}
  end

  @doc "Text message padded to 160 chars, long enough to be stored as a memo."
  def memo_message(text) do
    text
    |> String.pad_trailing(160, "-")
    |> then(&%Messages.Text{text: &1})
  end

  @doc """
  Alice posts `text` and an image, Bob posts an image; waits until all are saved.
  The usual three-message dialog for read/delete tests.
  """
  def add_text_and_two_images(dialog, alice, bob, text) do
    %Messages.Text{text: text} |> Dialogs.add_new_message(alice, dialog)
    "not_image" |> FakeData.image() |> Dialogs.add_new_message(alice, dialog)

    "not_image 2"
    |> FakeData.image()
    |> Dialogs.add_new_message(bob, dialog)
    |> Dialogs.await_saved(dialog)
  end
end
