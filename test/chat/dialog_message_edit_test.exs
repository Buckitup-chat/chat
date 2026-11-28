defmodule Chat.DialogMessageEditTest do
  use ChatWeb.DataCase, async: true

  import Chat.Test.DialogsFixtures,
    only: [add_text_and_two_images: 4, alice_bob_dialog: 0, memo_message: 1]

  alias Chat.Content.Files
  alias Chat.Content.Memo
  alias Chat.Db.ChangeTracker
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.Utils.StorageId
  alias Support.FakeData

  @text "Alice welcomes Bob"

  test "removed by author message should not be present in dialog" do
    {alice, bob, _bob_card, dialog} = alice_bob_dialog()
    add_text_and_two_images(dialog, alice, bob, @text)

    msg_id = find_message_id(dialog, bob, @text)
    assert msg_id != nil

    dialog |> Dialogs.delete(alice, msg_id)
    ChangeTracker.await()

    assert nil == find_message_id(dialog, bob, @text)
  end

  test "message cannot be removed by a peer in dialog" do
    {alice, bob, _bob_card, dialog} = alice_bob_dialog()
    add_text_and_two_images(dialog, alice, bob, @text)

    msg_id = find_message_id(dialog, bob, @text)
    assert msg_id != nil

    dialog |> Dialogs.delete(bob, msg_id)

    assert nil != find_message_id(dialog, bob, @text)
  end

  test "message removal should remove content as well" do
    {alice, _, _, dialog} = alice_bob_dialog()

    "memo here" |> memo_message() |> Dialogs.add_new_message(alice, dialog)
    "not_image" |> FakeData.image() |> Dialogs.add_new_message(alice, dialog)

    FakeData.file()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    dialog
    |> Dialogs.read(alice)
    |> Enum.zip([&Memo.get/1, &Files.get/1, &Files.get/1])
    |> Enum.map(fn {msg, getter} ->
      assert nil != msg.content |> StorageId.from_json() |> then(getter)
      dialog |> Dialogs.delete(alice, {msg.index, msg.id})
      ChangeTracker.await()
      assert nil == msg.content |> StorageId.from_json() |> then(getter)
    end)
  end

  test "message update should replace previous version in dialog" do
    {alice, _, _, dialog} = alice_bob_dialog()
    text = "text here"
    updated_text = "updated text here" |> String.pad_trailing(200, "-")

    "memo here" |> memo_message() |> Dialogs.add_new_message(alice, dialog)

    %Messages.Text{text: text}
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    assert [_, msg] = dialog |> Dialogs.read(alice)
    assert ^text = msg.content

    msg_id = {msg.index, msg.id}
    update_text(dialog, alice, msg_id, updated_text)

    assert [_, %{type: :memo} = msg] = dialog |> Dialogs.read(alice)
    assert ^updated_text = msg.content |> StorageId.from_json() |> Memo.get()

    update_text(dialog, alice, msg_id, text)

    assert [_, %{type: :text, content: ^text}] = dialog |> Dialogs.read(alice)
  end

  # --- Helpers ---

  defp find_message_id(dialog, reader, text) do
    dialog
    |> Dialogs.read(reader)
    |> Enum.find(&(&1.content == text))
    |> then(fn
      nil -> nil
      msg -> {msg.index, msg.id}
    end)
  end

  defp update_text(dialog, author, msg_id, text) do
    text
    |> Messages.Text.new(0)
    |> Dialogs.update_message(msg_id, author, dialog)
    |> Dialogs.await_saved(dialog)
  end
end
