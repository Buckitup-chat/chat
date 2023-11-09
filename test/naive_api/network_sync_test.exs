defmodule NailveApi.NetworkSyncTest do
  use ExUnit.Case

  test "all keys serialization" do
    make_all_possible_types_of_data()

    assert no_keys_lost_after_serialization?()

    assert deserialized_correctly?()
  end



end
