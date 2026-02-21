defmodule Chat.Proto.ShortcodeTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Schemas.UserCard
  alias Chat.Proto.Shortcode

  describe "short_code/1" do
    test "extracts bytes 2-4 from user_hash and encodes as lowercase hex" do
      # user_hash: 0x01aabbccdddddddd...
      user_hash = <<0x01, 0xAA, 0xBB, 0xCC, 0xDD, 0xDD, 0xDD, 0xDD>>
      user_card = %UserCard{user_hash: user_hash}

      assert Shortcode.short_code(user_card) == "aabbcc"
    end

    test "works with different prefix bytes" do
      # user_hash: 0x02112233445566...
      user_hash = <<0x02, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77>>
      user_card = %UserCard{user_hash: user_hash}

      assert Shortcode.short_code(user_card) == "112233"
    end

    test "encodes lowercase hex" do
      # user_hash: 0x00ABCDEF123456...
      user_hash = <<0x00, 0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56, 0x78>>
      user_card = %UserCard{user_hash: user_hash}

      assert Shortcode.short_code(user_card) == "abcdef"
    end
  end
end
