defmodule Chat.Data.Types.PrefixedHashTest do
  use ExUnit.Case, async: true

  defmodule SampleHash do
    @moduledoc false
    use Chat.Data.Types.PrefixedHash, prefix: "smp_"
  end

  @binary :crypto.strong_rand_bytes(64)
  @hex Base.encode16(@binary, case: :lower)

  test "type is string" do
    assert SampleHash.type() == :string
  end

  describe "cast/1" do
    test "accepts prefixed hex in any case and downcases it" do
      assert SampleHash.cast("smp_" <> String.upcase(@hex)) == {:ok, "smp_" <> @hex}
    end

    test "rejects wrong prefix, wrong length and non-hex" do
      assert SampleHash.cast("u_" <> @hex) == :error
      assert SampleHash.cast("smp_" <> String.slice(@hex, 1..-1//1)) == :error
      assert SampleHash.cast("smp_" <> String.duplicate("zz", 64)) == :error
      assert SampleHash.cast(nil) == :error
    end
  end

  test "dump/1 downcases prefixed values and rejects others" do
    assert SampleHash.dump("smp_ABC") == {:ok, "smp_abc"}
    assert SampleHash.dump("u_abc") == :error
  end

  test "load/1 keeps prefixed values and rejects others" do
    assert SampleHash.load("smp_abc") == {:ok, "smp_abc"}
    assert SampleHash.load("u_abc") == :error
  end

  test "from_binary/1 and to_binary/1 round-trip" do
    hash = SampleHash.from_binary(@binary)

    assert hash == "smp_" <> @hex
    assert SampleHash.to_binary(hash) == @binary
    assert SampleHash.to_binary("smp_zz") == nil
  end
end
