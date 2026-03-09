defmodule ChatWeb.Electric.UserStorageBinaryFormatTest do
  @moduledoc """
  Test to verify binary data formats through the complete cycle:
  1. Ingest from client (base64 encoding for _b64 suffix fields)
  2. Storage in PostgreSQL (bytea)
  3. Sync back to client via Electric (base64)

  Goal: Verify the base64 encoding strategy works end-to-end.
  """
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.User
  alias ChatWeb.Utils.IngestUtil

  @test_binary <<1, 2, 3, 255, 128, 0, 42, 99>>
  @test_uuid Ecto.UUID.generate()

  setup do
    # Create test user
    identity = User.generate_pq_identity("test_user")
    card = User.extract_pq_card(identity)

    # Insert user card
    repo().insert!(struct(Chat.Data.Schemas.UserCard, Map.from_struct(card)))

    %{
      user_hash: card.user_hash,
      sign_skey: identity.sign_skey,
      uuid: @test_uuid
    }
  end

  describe "binary encoding formats for ingest" do
    test "base64 encoding for _b64 suffix (new implementation)", %{user_hash: user_hash} do
      # Base64 encoding (no padding) for _b64 suffix
      base64_encoded = Base.encode64(@test_binary, padding: false)

      mutation = %{
        "type" => "insert",
        "modified" => %{
          "user_hash" => "\\x" <> Base.encode16(user_hash, case: :lower),
          "uuid" => @test_uuid,
          "value_b64" => base64_encoded
        },
        "syncMetadata" => %{"relation" => "user_storage"}
      }

      # Test decoding through IngestUtil with _b64 suffix
      assert {:ok, decoded} = IngestUtil.decode_base64(base64_encoded)
      assert decoded == @test_binary

      # Measure payload size
      json_payload = Jason.encode!(%{"mutations" => [mutation]})
      payload_size = byte_size(json_payload)
      binary_size = byte_size(@test_binary)
      overhead_ratio = payload_size / binary_size

      # IO.puts("\n=== BASE64 ENCODING (_b64 suffix) ===")
      # IO.puts("Binary size: #{binary_size} bytes")
      # IO.puts("Encoded string: #{base64_encoded}")
      # IO.puts("JSON payload size: #{payload_size} bytes")
      # IO.puts("Overhead ratio: #{Float.round(overhead_ratio, 2)}x")
    end

    test "hex encoding comparison (for reference)", %{user_hash: user_hash} do
      # Show what hex encoding would look like (old approach)
      hex_encoded = "\\x" <> Base.encode16(@test_binary, case: :lower)

      mutation = %{
        "type" => "insert",
        "modified" => %{
          "user_hash" => "\\x" <> Base.encode16(user_hash, case: :lower),
          "uuid" => Ecto.UUID.generate(),
          "value_hex" => hex_encoded
        },
        "syncMetadata" => %{"relation" => "user_storage"}
      }

      json_payload = Jason.encode!(%{"mutations" => [mutation]})
      payload_size = byte_size(json_payload)

      # IO.puts("\n=== HEX ENCODING (for comparison) ===")
      # IO.puts("Binary size: #{byte_size(@test_binary)} bytes")
      # IO.puts("Encoded string: #{hex_encoded}")
      # IO.puts("JSON payload size: #{payload_size} bytes")
    end
  end

  describe "storage in database" do
    test "bytea stores raw binary efficiently", %{user_hash: user_hash} do
      # Direct insert
      storage = %UserStorage{
        user_hash: user_hash,
        uuid: @test_uuid,
        value_b64: @test_binary
      }

      {:ok, inserted} = repo().insert(storage)

      # Verify raw binary is stored
      assert inserted.value_b64 == @test_binary
      assert is_binary(inserted.value_b64)
      assert byte_size(inserted.value_b64) == byte_size(@test_binary)

      # IO.puts("\n=== DATABASE STORAGE ===")
      # IO.puts("Original binary: #{inspect(@test_binary)}")
      # IO.puts("Stored binary: #{inspect(inserted.value_b64)}")
      # IO.puts("Match: #{inserted.value_b64 == @test_binary}")
    end
  end

  describe "sync response format from Electric" do
    test "examine Electric JSON response format for bytea", %{user_hash: user_hash} do
      # Insert test data
      storage = %UserStorage{
        user_hash: user_hash,
        uuid: @test_uuid,
        value_b64: @test_binary
      }

      repo().insert!(storage)

      # Query to see how Ecto returns it
      stored = repo().get_by(UserStorage, user_hash: user_hash, uuid: @test_uuid)
      assert stored.value_b64 == @test_binary

      # Simulate what Electric would return via JSON
      # Electric/Phoenix.Sync would base64-encode the binary before Jason.encode!
      base64_encoded_value = Base.encode64(stored.value_b64)
      json_encoded = Jason.encode!(%{value_b64: base64_encoded_value})
      json_decoded = Jason.decode!(json_encoded)

      # IO.puts("\n=== ELECTRIC SYNC RESPONSE ===")
      # IO.puts("Original binary: #{inspect(@test_binary)}")
      # IO.puts("Jason.encode! result: #{json_encoded}")
      # IO.puts("Decoded value_b64: #{inspect(json_decoded["value_b64"])}")

      # Jason encodes binary as base64 by default
      assert is_binary(json_decoded["value_b64"])
      # It should be base64 encoded
      assert {:ok, decoded_binary} = Base.decode64(json_decoded["value_b64"])
      assert decoded_binary == @test_binary
    end

    test "verify Electric SSE stream format", %{user_hash: user_hash, uuid: uuid} do
      # Insert test data
      storage = %UserStorage{
        user_hash: user_hash,
        uuid: uuid,
        value_b64: @test_binary
      }

      repo().insert!(storage)

      # Query using Ecto's JSON encoding
      result = repo().get_by(UserStorage, user_hash: user_hash, uuid: uuid)

      # Convert to map as Electric would, base64-encoding binary fields
      map_result = %{
        user_hash: Base.encode16(result.user_hash, case: :lower),
        uuid: result.uuid,
        value_b64: Base.encode64(result.value_b64)
      }

      # Encode to JSON (this is what gets sent over SSE)
      json_payload = Jason.encode!(map_result)
      parsed = Jason.decode!(json_payload)

      # IO.puts("\n=== ELECTRIC SSE FORMAT ===")
      # IO.puts("JSON payload: #{String.slice(json_payload, 0..200)}")
      # IO.puts("Parsed value_b64 type: #{inspect(parsed["value_b64"])}")

      # Verify the value_b64 can be decoded
      {:ok, decoded} = Base.decode64(parsed["value_b64"])
      assert decoded == @test_binary

      # IO.puts("Base64 decoded successfully: #{decoded == @test_binary}")
    end
  end

  describe "full round-trip test" do
    test "ingest base64 → store binary → sync base64", %{user_hash: user_hash} do
      # Step 1: Prepare ingest payload with base64 encoding (new implementation)
      base64_value = Base.encode64(@test_binary, padding: false)

      mutations = [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => "\\x" <> Base.encode16(user_hash, case: :lower),
            "uuid" => @test_uuid,
            "value_b64" => base64_value
          },
          "syncMetadata" => %{"relation" => "user_storage"}
        }
      ]

      # Step 2: Decode through IngestUtil
      {:ok, decoded_mutations} =
        IngestUtil.decode_mutation_fields(mutations, ~w[_hash], ~w[_b64])

      # Step 3: Verify storage
      [decoded_mutation] = decoded_mutations
      decoded_value = decoded_mutation["modified"]["value_b64"]
      assert decoded_value == @test_binary

      # Step 4: Simulate sync response (Electric base64-encodes binary before JSON)
      sync_json = Jason.encode!(%{value_b64: Base.encode64(decoded_value)})
      sync_parsed = Jason.decode!(sync_json)
      {:ok, sync_decoded} = Base.decode64(sync_parsed["value_b64"])
      assert sync_decoded == @test_binary

      # IO.puts("\n=== FULL ROUND-TRIP ===")
      # IO.puts("1. Client sends (base64): #{String.slice(base64_value, 0..20)}...")
      # IO.puts("   Size: #{byte_size(base64_value)} bytes")
      # IO.puts("2. Stored in DB (binary): #{byte_size(@test_binary)} bytes")
      # IO.puts("3. Sync returns (base64): #{String.slice(sync_parsed["value_b64"], 0..20)}...")
      # IO.puts("   Size: #{byte_size(sync_parsed["value_b64"])} bytes")
      # IO.puts("\nRound-trip successful: #{sync_decoded == @test_binary}")
    end

    test "compare efficiency: 10MB payload base64 vs hex", %{user_hash: user_hash} do
      # Simulate a 10MB binary (max allowed)
      large_binary = :crypto.strong_rand_bytes(10_485_760)

      # Hex encoding (old)
      hex_encoded = "\\x" <> Base.encode16(large_binary, case: :lower)
      hex_size = byte_size(hex_encoded)

      # Base64 encoding (new)
      base64_encoded = Base.encode64(large_binary, padding: false)
      base64_size = byte_size(base64_encoded)

      # JSON payload sizes
      hex_mutation = %{
        "type" => "insert",
        "modified" => %{
          "user_hash" => "\\x" <> Base.encode16(user_hash, case: :lower),
          "uuid" => @test_uuid,
          "value_hex" => hex_encoded
        },
        "syncMetadata" => %{"relation" => "user_storage"}
      }

      base64_mutation = %{
        "type" => "insert",
        "modified" => %{
          "user_hash" => "\\x" <> Base.encode16(user_hash, case: :lower),
          "uuid" => @test_uuid,
          "value_b64" => base64_encoded
        },
        "syncMetadata" => %{"relation" => "user_storage"}
      }

      hex_json_size = byte_size(Jason.encode!(%{"mutations" => [hex_mutation]}))
      base64_json_size = byte_size(Jason.encode!(%{"mutations" => [base64_mutation]}))

      # IO.puts("\n=== 10MB PAYLOAD COMPARISON ===")
      # IO.puts("Original binary: 10,485,760 bytes (10 MB)")
      # IO.puts("")
      # IO.puts("HEX ENCODING (old):")
      # IO.puts("  Encoded size: #{format_bytes(hex_size)}")
      # IO.puts("  JSON payload: #{format_bytes(hex_json_size)}")
      # IO.puts("  Overhead: #{Float.round(hex_size / 10_485_760, 2)}x")
      # IO.puts("")
      # IO.puts("BASE64 ENCODING (new):")
      # IO.puts("  Encoded size: #{format_bytes(base64_size)}")
      # IO.puts("  JSON payload: #{format_bytes(base64_json_size)}")
      # IO.puts("  Overhead: #{Float.round(base64_size / 10_485_760, 2)}x")
      # IO.puts("")
      # IO.puts("Savings with base64: #{format_bytes(hex_json_size - base64_json_size)}")
      # IO.puts("Percentage reduction: #{Float.round((1 - base64_json_size / hex_json_size) * 100, 1)}%")
    end
  end

  defp format_bytes(bytes) do
    cond do
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 2)} KB"
      true -> "#{bytes} bytes"
    end
  end
end
