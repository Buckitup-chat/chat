defmodule NaiveApi.NetworkSyncFailsafeTest do
  use ExUnit.Case, async: true

  test "deserialize_value" do
    term =
      &((&1 + 1)
        |> :erlang.term_to_binary([:compress])
        |> Base.url_encode64())

    refute NaiveApi.Data.deserialize_value(term)
    refute NaiveApi.Data.deserialize_value(123)
  end

  test "serialize_key" do
    refute NaiveApi.Data.serialize_key(:not_tuple)
  end

  test "deserialize_key" do
    refute NaiveApi.Data.deserialize_key(:not_string)
    refute NaiveApi.Data.deserialize_key("some_unknown_key/123")
  end
end
