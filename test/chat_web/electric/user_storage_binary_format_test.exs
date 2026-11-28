defmodule ChatWeb.Electric.UserStorageBinaryFormatTest do
  @moduledoc """
  Test to verify binary data formats through the complete cycle:
  1. Ingest from client (base64 encoding for _b64 suffix fields)
  2. Storage in PostgreSQL (bytea)
  3. Sync back to client via Electric (base64)

  Goal: Verify the base64 encoding strategy works end-to-end.
  """
  use ChatWeb.ConnCase, async: true, group: :electric_http
  use ChatWeb.DataCase

  import Chat.Db, only: [repo: 0]
  import Chat.Test.UserStorageFixtures, only: [user_with_card: 1, signed_storage: 3]

  alias Chat.Data.Schemas.UserStorage
  alias ChatWeb.Utils.IngestUtil

  @test_binary <<1, 2, 3, 255, 128, 0, 42, 99>>
  @test_uuid Ecto.UUID.generate()

  setup :user_with_card

  describe "binary encoding formats for ingest" do
    test "base64 encoding for _b64 suffix (new implementation)" do
      base64_encoded = Base.encode64(@test_binary, padding: false)

      assert {:ok, decoded} = IngestUtil.decode_base64(base64_encoded)
      assert decoded == @test_binary
    end

    test "hex encoding comparison (for reference)", %{user_hash: user_hash} do
      hex_encoded = "\\x" <> Base.encode16(@test_binary, case: :lower)
      base64_encoded = Base.encode64(@test_binary, padding: false)

      hex_size = user_hash |> insert_mutation("value_hex", hex_encoded) |> payload_size()
      base64_size = user_hash |> insert_mutation("value_b64", base64_encoded) |> payload_size()

      assert base64_size < hex_size
    end
  end

  describe "storage in database" do
    test "bytea stores raw binary efficiently", ctx do
      {:ok, inserted} = ctx |> test_storage(@test_uuid) |> repo().insert()

      assert inserted.value_b64 == @test_binary
      assert is_binary(inserted.value_b64)
      assert byte_size(inserted.value_b64) == byte_size(@test_binary)
    end
  end

  describe "sync response format from Electric" do
    test "examine Electric JSON response format for bytea", %{user_hash: user_hash} = ctx do
      ctx |> test_storage(@test_uuid) |> repo().insert!()

      stored = repo().get_by(UserStorage, user_hash: user_hash, uuid: @test_uuid)
      assert stored.value_b64 == @test_binary

      # Electric/Phoenix.Sync base64-encodes the binary before Jason.encode!
      json_decoded =
        %{value_b64: Base.encode64(stored.value_b64)} |> Jason.encode!() |> Jason.decode!()

      assert is_binary(json_decoded["value_b64"])
      assert {:ok, decoded_binary} = Base.decode64(json_decoded["value_b64"])
      assert decoded_binary == @test_binary
    end

    test "verify Electric SSE stream format", %{user_hash: user_hash} = ctx do
      uuid = @test_uuid
      ctx |> test_storage(uuid) |> repo().insert!()

      result = repo().get_by(UserStorage, user_hash: user_hash, uuid: uuid)

      parsed =
        %{
          user_hash: Base.encode16(result.user_hash, case: :lower),
          uuid: result.uuid,
          value_b64: Base.encode64(result.value_b64)
        }
        |> Jason.encode!()
        |> Jason.decode!()

      {:ok, decoded} = Base.decode64(parsed["value_b64"])
      assert decoded == @test_binary
    end
  end

  describe "full round-trip test" do
    test "ingest base64 → store binary → sync base64", %{user_hash: user_hash} do
      mutations = [
        insert_mutation(user_hash, "value_b64", Base.encode64(@test_binary, padding: false))
      ]

      {:ok, [decoded_mutation]} =
        IngestUtil.decode_mutation_fields(mutations, ~w[_hash], ~w[_b64])

      decoded_value = decoded_mutation["modified"]["value_b64"]
      assert decoded_value == @test_binary

      sync_parsed =
        %{value_b64: Base.encode64(decoded_value)} |> Jason.encode!() |> Jason.decode!()

      {:ok, sync_decoded} = Base.decode64(sync_parsed["value_b64"])
      assert sync_decoded == @test_binary
    end

    test "compare efficiency: 10MB payload base64 vs hex", %{user_hash: user_hash} do
      large_binary = :crypto.strong_rand_bytes(10_485_760)
      hex_encoded = "\\x" <> Base.encode16(large_binary, case: :lower)
      base64_encoded = Base.encode64(large_binary, padding: false)

      hex_json_size = user_hash |> insert_mutation("value_hex", hex_encoded) |> payload_size()

      base64_json_size =
        user_hash |> insert_mutation("value_b64", base64_encoded) |> payload_size()

      assert base64_json_size < hex_json_size
    end
  end

  defp test_storage(%{identity: identity, user_hash: user_hash}, uuid),
    do: signed_storage(identity, user_hash, %{uuid: uuid, value_b64: @test_binary})

  defp insert_mutation(user_hash, field, value) do
    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => "\\x" <> Base.encode16(user_hash, case: :lower),
        "uuid" => @test_uuid,
        field => value
      },
      "syncMetadata" => %{"relation" => "user_storage"}
    }
  end

  defp payload_size(mutation), do: %{"mutations" => [mutation]} |> Jason.encode!() |> byte_size()
end
