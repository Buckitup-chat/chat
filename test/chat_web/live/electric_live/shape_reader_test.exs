defmodule ChatWeb.ElectricLive.ShapeReaderTest do
  @moduledoc """
  The shape log fold.

  A shape Electric already has cached replays as a snapshot of inserts followed by
  every change since, so reading only the inserts returns rows as they stood before
  their first update — which is how an edited review came back with its old
  `sign_hash` and looked like a concurrent edit.
  """
  use ExUnit.Case, async: true

  alias ChatWeb.ElectricLive.ShapeReader
  alias Electric.Client.Message.ChangeMessage
  alias Electric.Client.Message.ControlMessage
  alias Electric.Client.Message.Headers

  defp change(operation, key, value) do
    %ChangeMessage{key: key, value: value, headers: %Headers{operation: operation}}
  end

  defp up_to_date, do: %ControlMessage{control: :up_to_date}

  test "returns the rows of a snapshot" do
    rows =
      ShapeReader.fold([
        change(:insert, "a", %{id: "a", v: 1}),
        change(:insert, "b", %{id: "b", v: 1}),
        up_to_date()
      ])

    assert Enum.sort_by(rows, & &1.id) == [%{id: "a", v: 1}, %{id: "b", v: 1}]
  end

  test "an update replaces the row it applies to" do
    rows =
      ShapeReader.fold([
        change(:insert, "a", %{id: "a", v: 1}),
        change(:insert, "b", %{id: "b", v: 1}),
        change(:update, "a", %{id: "a", v: 2}),
        up_to_date()
      ])

    assert Enum.sort_by(rows, & &1.id) == [%{id: "a", v: 2}, %{id: "b", v: 1}]
  end

  test "the last update wins" do
    rows =
      ShapeReader.fold([
        change(:insert, "a", %{id: "a", v: 1}),
        change(:update, "a", %{id: "a", v: 2}),
        change(:update, "a", %{id: "a", v: 3}),
        up_to_date()
      ])

    assert rows == [%{id: "a", v: 3}]
  end

  test "a delete drops the row" do
    rows =
      ShapeReader.fold([
        change(:insert, "a", %{id: "a", v: 1}),
        change(:insert, "b", %{id: "b", v: 1}),
        change(:delete, "a", %{id: "a", v: 1}),
        up_to_date()
      ])

    assert rows == [%{id: "b", v: 1}]
  end

  test "stops at up_to_date and ignores anything after it" do
    rows =
      ShapeReader.fold([
        change(:insert, "a", %{id: "a", v: 1}),
        up_to_date(),
        change(:update, "a", %{id: "a", v: 99})
      ])

    assert rows == [%{id: "a", v: 1}]
  end

  test "an empty shape yields no rows" do
    assert ShapeReader.fold([up_to_date()]) == []
  end
end
