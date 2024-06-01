defmodule Enigma.SecretGenerationTest do
  use ExUnit.Case, async: true

  test "generated secret should be same size and do not repeat" do
    first_secret = Enigma.generate_secret()
    second_secret = Enigma.generate_secret()

    assert first_secret != second_secret
    assert [first_secret, second_secret] |> Enum.all?(&(byte_size(&1) == 32))
  end
end
