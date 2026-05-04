defmodule Chat.Proto.ShortcodeTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Schemas.UserCard
  alias Chat.Proto.Shortcode

  describe "short_code/1" do
    test "extracts first 6 hex characters after u_ prefix" do
      user_hash = "u_" <> String.duplicate("aabbcc", 21) <> "aa"
      user_card = %UserCard{user_hash: user_hash}

      assert Shortcode.short_code(user_card) == "aabbcc"
    end

    test "works with different hash values" do
      user_hash = "u_" <> "112233" <> String.duplicate("00", 61)
      user_card = %UserCard{user_hash: user_hash}

      assert Shortcode.short_code(user_card) == "112233"
    end

    test "returns lowercase hex" do
      user_hash = "u_" <> "abcdef" <> String.duplicate("00", 61)
      user_card = %UserCard{user_hash: user_hash}

      assert Shortcode.short_code(user_card) == "abcdef"
    end
  end
end
