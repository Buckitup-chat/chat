defmodule Chat.TimeTest do
  use ExUnit.Case
  alias Chat.Time

  test "should decide time correctly" do
    assert :lt =
             DateTime.compare(
               ~U[2023-01-01 01:01:01Z],
               Time.decide_time()
             )
  end
end
