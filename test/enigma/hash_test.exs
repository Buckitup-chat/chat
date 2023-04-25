defmodule Enigma.HashTest do
  use ExUnit.Case, async: true

  test "hash should work" do
    assert <<140, 166, 110, 230, 178, 254, 75, 185, 40, 168, 227, 205, 47, 80, 141, 228, 17, 156,
             8, 149, 242, 46, 1, 17, 23, 226, 44, 249, 177, 61, 231, 239>> = Enigma.hash("Hello")
  end

  test "short_hash should work" do
    assert "8ca66e" = Enigma.short_hash("Hello")
  end
end
