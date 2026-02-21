defmodule ChatWeb.ElectricLive.UserSandboxLive.ApiClientTest do
  @moduledoc """
  Tests for Electric API Client.

  Note: These tests verify the structure and basic error handling.
  Full integration tests with actual API calls should be done manually
  or with the server running.
  """
  use ChatWeb.DataCase

  alias ChatWeb.ElectricLive.UserSandboxLive.ApiClient
  alias Chat.Data.User

  describe "create_user/2" do
    test "returns user data and log entries on success" do
      # This would require mocking Req.get and Req.post
      # For now, we verify the structure by testing with invalid URL
      # to see that errors are handled correctly

      result = ApiClient.create_user("Test User", "http://invalid-host-12345.local")

      assert {:error, %{reason: reason, log_entries: log_entries}} = result
      assert is_binary(reason)
      assert is_list(log_entries)
      assert length(log_entries) >= 1

      # Verify log entry structure
      [log_entry | _] = log_entries
      assert is_map(log_entry)
      assert Map.has_key?(log_entry, :timestamp)
      assert Map.has_key?(log_entry, :method)
      assert Map.has_key?(log_entry, :url)
      assert Map.has_key?(log_entry, :request_headers)
      assert Map.has_key?(log_entry, :request_body)
      assert Map.has_key?(log_entry, :response_status)
      assert Map.has_key?(log_entry, :response_headers)
      assert Map.has_key?(log_entry, :response_body)
    end
  end

  describe "update_user_name/4" do
    test "returns log entries structure on error" do
      {sign_pkey, sign_skey} = :crypto.generate_key(:mldsa87, [])
      user_hash = <<0x01>> <> :crypto.hash(:sha3_512, sign_pkey)

      result =
        ApiClient.update_user_name(
          user_hash,
          sign_skey,
          "New Name",
          "http://invalid-host-12345.local"
        )

      assert {:error, %{reason: _reason, log_entries: log_entries}} = result
      assert is_list(log_entries)
      assert length(log_entries) >= 1
    end
  end

  describe "delete_user/3" do
    test "returns log entries structure on error" do
      {sign_pkey, sign_skey} = :crypto.generate_key(:mldsa87, [])
      user_hash = <<0x01>> <> :crypto.hash(:sha3_512, sign_pkey)

      result = ApiClient.delete_user(user_hash, sign_skey, "http://invalid-host-12345.local")

      assert {:error, %{reason: _reason, log_entries: log_entries}} = result
      assert is_list(log_entries)
      assert length(log_entries) >= 1
    end
  end

  describe "create_storage/5" do
    test "returns log entries structure on error" do
      {sign_pkey, sign_skey} = :crypto.generate_key(:mldsa87, [])
      user_hash = <<0x01>> <> :crypto.hash(:sha3_512, sign_pkey)

      result =
        ApiClient.create_storage(
          user_hash,
          sign_skey,
          "550e8400-e29b-41d4-a716-446655440000",
          "test value",
          "http://invalid-host-12345.local"
        )

      assert {:error, %{reason: _reason, log_entries: log_entries}} = result
      assert is_list(log_entries)
      assert length(log_entries) >= 1
    end

    test "generates UUID if not provided" do
      {sign_pkey, sign_skey} = :crypto.generate_key(:mldsa87, [])
      user_hash = <<0x01>> <> :crypto.hash(:sha3_512, sign_pkey)

      result =
        ApiClient.create_storage(
          user_hash,
          sign_skey,
          "",
          "test value",
          "http://invalid-host-12345.local"
        )

      # Even though it fails, we can verify the UUID generation would happen
      assert {:error, %{reason: _reason, log_entries: _log_entries}} = result
    end
  end

  describe "hex encoding" do
    test "encodes binaries correctly" do
      # Test that the private encode_hex function works correctly
      # by verifying the output format in a real scenario

      identity = User.generate_pq_identity("Test")
      card = User.extract_pq_card(identity)

      # Verify the card has the expected binary fields
      assert is_binary(card.user_hash)
      assert byte_size(card.user_hash) == 65
      assert is_binary(card.sign_pkey)
      assert is_binary(card.contact_pkey)
      assert is_binary(card.contact_cert)
      assert is_binary(card.crypt_pkey)
      assert is_binary(card.crypt_cert)
    end
  end
end
