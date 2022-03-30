defmodule Chat.UtilsTest do
  use ExUnit.Case, async: true

  alias Chat.Utils

  test "blob crypt" do
    data = "1234"
    type = "text/plain"

    {encrypted, secret} = Utils.encrypt_blob({data, type})

    assert encrypted != {data, type}

    assert {^data, ^type} = Utils.decrypt_blob(encrypted, secret)
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

  test "test binhash" do
    bin = :binary.copy(<<255>>, 32)

    assert "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" == Utils.hash(bin)
  end

  test "" do
    me = Chat.Identity.create("Alice")
    card = Chat.Card.from_identity(me)

    assert Utils.hash(me) == Utils.hash(card)
  end
end
