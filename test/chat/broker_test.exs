defmodule Chat.BrokerTest do
  use ExUnit.Case, async: true

  alias Chat.Broker

  test "broker should store any value, and give it once" do
    value = {"some value", :of, 'any type', 45}

    key = Broker.store(value)
    assert is_binary(key)

    assert ^value = Broker.get(key)
    assert nil == Broker.get(key)
  end
end
