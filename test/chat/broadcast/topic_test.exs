defmodule Chat.Broadcast.TopicTest do
  use ExUnit.Case, async: true

  alias Chat.Broadcast.Topic

  test "lobby" do
    assert Topic.lobby() == "chat::lobby"
  end

  test "dialog" do
    dialog = Chat.Dialogs.open(Chat.Identity.create("A"), Chat.Identity.create("B"))
    dialog_key = Chat.Dialogs.key(dialog)
    hex_dialog_key = Base.encode16(dialog_key, case: :lower)

    correct_topic = "dialog:#{hex_dialog_key}"

    assert Topic.dialog(dialog) == correct_topic
    assert Topic.dialog(dialog_key) == correct_topic
    assert Topic.dialog(hex_dialog_key) == correct_topic
  end
end
