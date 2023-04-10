defmodule Enigma.SecretSharingTest do
  use ExUnit.Case, async: true

  test "shares and recovers a secret properly" do
    key = Enigma.hash("hello")
    shares = Enigma.hide_secret_in_shares(key, 5, 4)
    assert length(shares) == 5

    # passing 4 shares instead of 5 should be enough to restore key and retrieve message
    assert key == shares |> tl() |> Enigma.recover_secret_from_shares()
  end

  test "fails on not enough shares" do
    key = Enigma.hash("hello")
    shares = Enigma.hide_secret_in_shares(key, 5, 4)
    assert length(shares) == 5

    # 3 shares when you need at least 4
    refute key ==
             shares
             |> tl()
             |> tl()
             |> Enigma.recover_secret_from_shares()
  end

  test "fails on bad share" do
    key = Enigma.hash("hello")
    shares = Enigma.hide_secret_in_shares(key, 5, 4)
    assert length(shares) == 5

    # one of the shares got jumbled in the process, which should skew the key
    refute key ==
             shares
             |> tl()
             |> List.update_at(0, &:crypto.strong_rand_bytes(byte_size(&1)))
             |> Enigma.recover_secret_from_shares()
  end

  test "failed sharing" do
    key = Enigma.hash("hello")

    try do
      Enigma.hide_secret_in_shares(5, 4, 3)
    rescue
      e in ArgumentError ->
        assert e.message == "byte_size of secret (which should be binary string) should be 32"
    end

    try do
      Enigma.hide_secret_in_shares(key, 257, 3)
    rescue
      e in ArgumentError ->
        assert e.message == "amount should be a number between 1 and 256, bounds not included"
    end

    try do
      Enigma.hide_secret_in_shares(key, 3, 4)
    rescue
      e in ArgumentError ->
        assert e.message == "threshold should be no more than amount"
    end
  end
end
