defmodule Chat.KeyRingTokens.KeyRingTest do
  use ExUnit.Case, async: true

  alias Chat.KeyRingTokens
  alias Chat.KeyRingTokens.Logic

  test "keyring token logic flow" do
    now = 3
    my_pid = self()

    assert {key, {^my_pid, code, ^now} = value} = token = Logic.generate_token_data(now)
    assert code > 9 and code < 100

    data =
      token
      |> Logic.exporter_data()

    assert {^key, ^code} = data

    pid_response =
      value
      |> Logic.valid_importer_pid(code, now + 10)

    assert {:ok, ^my_pid} = pid_response
    assert :error = Logic.valid_importer_pid(value, code, now + 1000)
  end

  test "leyring logic defaults" do
    my_pid = self()

    assert {_, {^my_pid, code, _} = value} = Logic.generate_token_data()
    assert {:ok, ^my_pid} = Logic.valid_importer_pid(value, code)
  end

  test "tokens case" do
    data = KeyRingTokens.create()

    assert {key, code} = data
    assert {:ok, self()} == KeyRingTokens.get(key, code)
  end
end
