defmodule Chat.DialogParcelTest do
  use ChatWeb.DataCase, async: true

  import Chat.Test.DialogsFixtures, only: [alice_bob_dialog: 0]

  alias Chat.Dialogs
  alias Chat.Messages

  describe "parsel_to_indexed_message/1" do
    test "extracts index and message from simple text parcel" do
      parcel = stored_parcel("Hello from Alice to Bob")

      {index, extracted_message} = Dialogs.parsel_to_indexed_message(parcel)

      assert is_integer(index)
      assert index > 0
      assert extracted_message.type == :text
      assert extracted_message.content != nil
    end

    test "extracts index and message from memo parcel with multiple items" do
      long_text = String.duplicate("This is a long memo message. ", 100)
      parcel = stored_parcel(long_text)

      assert length(parcel.data) > 1

      {index, extracted_message} = Dialogs.parsel_to_indexed_message(parcel)

      assert is_integer(index)
      assert index > 0
      assert extracted_message.type == :memo
      refute extracted_message.content == long_text
    end

    test "raises error when parcel has no dialog message" do
      empty_parcel = %Chat.SignedParcel{data: []}

      assert_raise ArgumentError, "Parcel does not contain a dialog message", fn ->
        Dialogs.parsel_to_indexed_message(empty_parcel)
      end

      non_dialog_parcel = %Chat.SignedParcel{data: [{{:memo, "some-id"}, "some content"}]}

      assert_raise ArgumentError, "Parcel does not contain a dialog message", fn ->
        Dialogs.parsel_to_indexed_message(non_dialog_parcel)
      end
    end

    test "handles parcel with dialog message among other items" do
      parcel = "This is a long memo message. " |> String.duplicate(100) |> stored_parcel()

      assert length(parcel.data) > 1
      assert Enum.any?(parcel.data, fn {key, _} -> match?({:memo, _}, key) end)
      assert Enum.any?(parcel.data, fn {key, _} -> match?({:dialog_message, _, _, _}, key) end)

      {index, extracted_message} = Dialogs.parsel_to_indexed_message(parcel)

      assert is_integer(index)
      assert extracted_message.type == :memo
    end
  end

  defp stored_parcel(text) do
    {alice, _bob, _bob_card, dialog} = alice_bob_dialog()

    %Messages.Text{text: text}
    |> Chat.SignedParcel.wrap_dialog_message(dialog, alice)
    |> Chat.store_parcel()
  end
end
