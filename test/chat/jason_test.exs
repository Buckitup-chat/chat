defmodule Chat.JasonTest do
  use ExUnit.Case, async: true

  describe "encode" do
    test "properly encodes a tuple" do
      assert Jason.encode({:ok, "success"}) == {:ok, "[\"ok\",\"success\"]"}
    end
  end
end
