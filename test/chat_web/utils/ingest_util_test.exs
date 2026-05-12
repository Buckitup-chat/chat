defmodule ChatWeb.Utils.IngestUtilTest do
  use ExUnit.Case, async: true

  alias ChatWeb.Utils.IngestUtil

  describe "decode_binary/1" do
    test "decodes values with hex prefixes" do
      assert {:ok, <<0xAB, 0xCD>>} = IngestUtil.decode_binary("\\xABCD")
      assert {:ok, <<0xAB, 0xCD>>} = IngestUtil.decode_binary("0xabcd")
    end

    test "returns raw binary string when no prefix is present" do
      assert {:ok, "plain"} = IngestUtil.decode_binary("plain")
    end

    test "returns error for invalid values" do
      assert {:error, "invalid_binary_field"} = IngestUtil.decode_binary("\\xzz")
      assert {:error, "invalid_binary_field"} = IngestUtil.decode_binary(123)
    end
  end

  describe "decode_mutation_fields/2" do
    test "decodes fields by suffix across sections and preserves others" do
      hex_suffixes = ~w[_hash]
      base64_suffixes = ~w[_pkey _cert]

      mutations = [
        %{
          "modified" => %{
            "sign_pkey" => Base.encode64(<<0xA1>>, padding: false),
            "contact_cert" => Base.encode64(<<0xB2>>, padding: false),
            "name" => "Bob"
          },
          "changes" => %{"user_hash" => "\\xC3"},
          "original" => %{"other" => 123},
          "type" => "insert"
        }
      ]

      assert {:ok, [decoded]} =
               IngestUtil.decode_mutation_fields(mutations, hex_suffixes, base64_suffixes)

      assert decoded["modified"]["sign_pkey"] == <<0xA1>>
      assert decoded["modified"]["contact_cert"] == <<0xB2>>
      assert decoded["modified"]["name"] == "Bob"
      assert decoded["changes"]["user_hash"] == <<0xC3>>
      assert decoded["original"]["other"] == 123
      assert decoded["type"] == "insert"
    end

    test "returns invalid_payload when an item is not a map" do
      assert {:error, "invalid_payload"} =
               IngestUtil.decode_mutation_fields(["bad"], ["_hash"], ["_pkey"])
    end

    test "returns invalid_base64_field when a suffix field has invalid base64" do
      mutations = [%{"modified" => %{"sign_pkey" => "\\xzz"}}]

      assert {:error, "invalid_base64_field"} =
               IngestUtil.decode_mutation_fields(mutations, ["_hash"], ["_pkey"])
    end

    test "decodes array values element-by-element for matching suffix" do
      bin_a = :crypto.strong_rand_bytes(8)
      bin_b = :crypto.strong_rand_bytes(8)

      mutations = [
        %{
          "modified" => %{
            "chunk_sign_hashes" => [
              Base.encode64(bin_a, padding: false),
              Base.encode64(bin_b, padding: false)
            ]
          }
        }
      ]

      assert {:ok, [decoded]} =
               IngestUtil.decode_mutation_fields(mutations, [], ["_hashes"])

      assert decoded["modified"]["chunk_sign_hashes"] == [bin_a, bin_b]
    end

    test "decodes empty array" do
      mutations = [%{"modified" => %{"chunk_sign_hashes" => []}}]

      assert {:ok, [decoded]} =
               IngestUtil.decode_mutation_fields(mutations, [], ["_hashes"])

      assert decoded["modified"]["chunk_sign_hashes"] == []
    end

    test "returns error for array with invalid base64 element" do
      mutations = [
        %{"modified" => %{"chunk_sign_hashes" => ["validbase64", "not!valid!"]}}
      ]

      assert {:error, "invalid_base64_field"} =
               IngestUtil.decode_mutation_fields(mutations, [], ["_hashes"])
    end
  end
end
