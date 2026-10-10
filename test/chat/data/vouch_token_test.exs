defmodule Chat.Data.VouchTokenTest do
  use ExUnit.Case, async: true

  alias Chat.Data.VouchToken

  describe "attenuates?/2" do
    test "exact match" do
      assert VouchToken.attenuates?("device.BK-001.storage.write", "device.BK-001.storage.write")
    end

    test "parent covers child" do
      assert VouchToken.attenuates?(
               "device.BK-001.storage.write",
               "device.BK-001.storage.write.dialog_messages"
             )
    end

    test "child does not cover parent" do
      refute VouchToken.attenuates?(
               "device.BK-001.storage.write.dialog_messages",
               "device.BK-001.storage.write"
             )
    end

    test "wildcard matches any segment" do
      assert VouchToken.attenuates?("device.*.storage.write", "device.BK-001.storage.write")
    end

    test "wildcard parent covers narrower child" do
      assert VouchToken.attenuates?(
               "device.*.storage.write",
               "device.BK-001.storage.write.dialog_messages"
             )
    end

    test "sibling scopes do not attenuate" do
      refute VouchToken.attenuates?("device.BK-001.storage.write", "device.BK-001.storage.read")
    end

    test "cross-tree scopes do not attenuate" do
      refute VouchToken.attenuates?("device.BK-001.admin", "origins.abc123.reviews.write")
    end

    test "root covers all descendants" do
      assert VouchToken.attenuates?("device", "device.BK-001.storage.write")
    end

    test "single segment exact match" do
      assert VouchToken.attenuates?("device", "device")
    end

    test "different roots" do
      refute VouchToken.attenuates?("device", "origins")
    end
  end
end
