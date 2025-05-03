defmodule Chat.UtilsTest do
  use ExUnit.Case, async: true

  alias Chat.Actor
  alias Chat.Identity
  alias Chat.Utils

  test "blob crypt" do
    data = "1234"
    type = "text/plain"
    secret = Enigma.generate_secret()

    encrypted = Enigma.cipher([data, type], secret)

    assert encrypted != {data, type}

    assert [^data, ^type] = Enigma.decipher(encrypted, secret)
  end

  test "pagination" do
    list = [
      %{timestamp: 100},
      %{timestamp: 19},
      %{timestamp: 18},
      %{timestamp: 18},
      %{timestamp: 15},
      %{timestamp: 11}
    ]

    assert [
             %{timestamp: 18},
             %{timestamp: 18}
           ] = Utils.page(list, 19, 2)
  end

  test "" do
    me = Identity.create("Alice")
    card = Chat.Card.from_identity(me)

    assert Enigma.hash(me) == Enigma.hash(card)
  end

  test "Actor encoding should work fine" do
    [me, room1, room2] =
      ["Alice", "room 1", "room 2"]
      |> Enum.map(&Identity.create/1)

    actor = Actor.new(me, [room1, room2], %{})
    password = "123456543211"

    encrypted =
      actor
      |> Actor.to_encrypted_json(password)

    assert is_binary(encrypted)

    decrypted = encrypted |> Actor.from_encrypted_json(password)

    assert decrypted.me == actor.me

    assert decrypted.rooms |> Enum.map(& &1.private_key) ==
             actor.rooms |> Enum.map(& &1.private_key)
  end

  test "trim_text should handle empty strings" do
    assert Utils.trim_text("") == [""]
  end

  test "trim_text should trim leading and trailing whitespace" do
    assert Utils.trim_text("  hello  ") == ["hello"]
  end

  test "trim_text should handle multiple lines" do
    text = """
    Line 1
    Line 2

    Line 4
    """
    
    expected = ["Line 1", "Line 2", "", "Line 4"]
    assert Utils.trim_text(text) == expected
  end

  test "trim_text should handle consecutive empty lines" do
    text = """
    Line 1


    Line 4
    """
    
    expected = ["Line 1", "", "Line 4"]
    assert Utils.trim_text(text) == expected
  end

  test "qr_base64_from_url should generate a base64 encoded QR code" do
    url = "https://example.com"
    result = Utils.qr_base64_from_url(url)
    
    assert is_binary(result)
    assert String.length(result) > 0
  end

  test "qr_base64_from_url should accept color option" do
    url = "https://example.com"
    result = Utils.qr_base64_from_url(url, color: "#FF0000")
    
    assert is_binary(result)
    assert String.length(result) > 0
  end

  test "qr_base64_from_url should accept background_opacity option" do
    url = "https://example.com"
    result = Utils.qr_base64_from_url(url, background_opacity: 0.5)
    
    assert is_binary(result)
    assert String.length(result) > 0
  end
end
