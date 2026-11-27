defmodule Chat.NetworkSynchronization.Electric.ShapeWriterBranchesTest.FakeShape do
  @moduledoc false

  def sync_required_parents(_op, _value), do: []
  def sync_derive_fields(value), do: value

  def sync_persist(_op, {:raise, error}), do: raise(error)
  def sync_persist(_op, {:return, result}), do: result
end

defmodule Chat.NetworkSynchronization.Electric.ShapeWriterBranchesTest.FakeShapes do
  @moduledoc false

  alias Chat.NetworkSynchronization.Electric.ShapeWriterBranchesTest.FakeShape

  def by_name(:fake), do: FakeShape
end

defmodule Chat.NetworkSynchronization.Electric.ShapeWriterBranchesTest do
  use ChatWeb.DataCase, async: true

  import ExUnit.CaptureLog
  import Rewire

  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.UserHash
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  rewire(ShapeWriter,
    Shapes: Chat.NetworkSynchronization.Electric.ShapeWriterBranchesTest.FakeShapes,
    as: FakeShapeWriter
  )

  describe "write errors" do
    test "repo not available is returned and logged" do
      log =
        capture_log(fn ->
          assert {:error, :repo_not_available} =
                   FakeShapeWriter.write(:fake, :insert, {:return, {:error, :repo_not_available}})
        end)

      assert log =~ "repo not available while writing :fake/:insert"
    end

    test "RuntimeError means the repo is not available" do
      log =
        capture_log(fn ->
          assert {:error, {:repo_not_available, %RuntimeError{message: "no repo"}}} =
                   FakeShapeWriter.write(
                     :fake,
                     :update,
                     {:raise, RuntimeError.exception("no repo")}
                   )
        end)

      assert log =~ "repo not available while writing :fake/:update: no repo"
    end

    test "Postgrex.Error is returned as a write failure" do
      error = %Postgrex.Error{message: "deadlock"}

      log =
        capture_log(fn ->
          assert {:error, ^error} = FakeShapeWriter.write(:fake, :insert, {:raise, error})
        end)

      assert log =~ "failed to write :fake/:insert"
    end

    test "persist error skips the after-persist hooks" do
      log =
        capture_log(fn ->
          assert {:error, :conflict} =
                   FakeShapeWriter.write(:fake, :insert, {:return, {:error, :conflict}})
        end)

      assert log =~ "failed to write :fake/:insert: :conflict"
    end
  end

  describe "composite parent key" do
    test "missing dialog_keys parent is looked up by its primary key and skipped" do
      receipt = %Chat.Data.Schemas.DialogMessageReceipt{
        peer_hash: random_hash(UserHash),
        dialog_hash: random_hash(DialogHash)
      }

      assert {:ok, :skipped_no_parent} =
               ShapeWriter.write(:dialog_message_receipts, :insert, receipt)
    end
  end

  # Helpers

  defp random_hash(type), do: 64 |> :crypto.strong_rand_bytes() |> type.from_binary()
end
