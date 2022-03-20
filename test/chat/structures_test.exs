defmodule Chat.StructuresTest do
  use ExUnit.Case, async: true

  test "dialog message" do
    struct = %Chat.Dialogs.Message{timestamp: 1, is_a_to_b?: false, a_copy: 2, b_copy: 3}

    assert "#Chat.Dialogs.Message<is_a_to_b?: false, timestamp: 1, type: nil, ...>" ==
             inspect(struct)
  end

  test "dialog.dialog" do
    struct = %Chat.Dialogs.Dialog{a_key: 1, b_key: 2, messages: [3, 4]}

    assert "#Chat.Dialogs.Dialog<messages: [3, 4], ...>" ==
             inspect(struct)
  end

  test "card" do
    struct = %Chat.Card{name: 1, pub_key: 2, hash: 3}

    assert "#Chat.Card<hash: 3, name: 1, ...>" ==
             inspect(struct)
  end
end
