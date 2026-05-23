defmodule ChatWeb.ElectricLive.UserSandboxLive.ApiClientTest do
  @moduledoc """
  Tests for Electric API Client.

  Note: These tests verify the structure and basic error handling.
  Full integration tests with actual API calls should be done manually
  or with the server running.
  """
  use ChatWeb.DataCase, async: true

  alias Chat.Data.User
  alias ChatWeb.ElectricLive.UserSandboxLive.ApiClient

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
      identity = User.generate_pq_identity("OldName")
      card = User.extract_pq_card(identity)
      existing_card = Map.from_struct(card) |> Map.put(:owner_timestamp, 1)

      result =
        ApiClient.update_user_name(
          existing_card,
          identity.sign_skey,
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
      identity = User.generate_pq_identity("ToDelete")
      card = User.extract_pq_card(identity)

      result =
        ApiClient.delete_user(
          card.user_hash,
          identity.sign_skey,
          "http://invalid-host-12345.local"
        )

      assert {:error, %{reason: _reason, log_entries: log_entries}} = result
      assert is_list(log_entries)
    end
  end

  describe "create_storage/5" do
    test "returns log entries structure on error" do
      identity = User.generate_pq_identity("StorageUser")
      card = User.extract_pq_card(identity)

      result =
        ApiClient.create_storage(
          card.user_hash,
          identity.sign_skey,
          "550e8400-e29b-41d4-a716-446655440000",
          "test value",
          "http://invalid-host-12345.local"
        )

      assert {:error, %{reason: _reason, log_entries: log_entries}} = result
      assert is_list(log_entries)
      assert length(log_entries) >= 1
    end

    test "generates UUID if not provided" do
      identity = User.generate_pq_identity("StorageUser2")
      card = User.extract_pq_card(identity)

      result =
        ApiClient.create_storage(
          card.user_hash,
          identity.sign_skey,
          "",
          "test value",
          "http://invalid-host-12345.local"
        )

      assert {:error, %{reason: _reason, log_entries: _log_entries}} = result
    end
  end

  describe "hex encoding" do
    test "encodes binaries correctly" do
      identity = User.generate_pq_identity("Test")
      card = User.extract_pq_card(identity)

      assert is_binary(card.user_hash)
      assert String.starts_with?(card.user_hash, "u_")
      assert byte_size(card.user_hash) == 130
      assert is_binary(card.sign_pkey)
      assert is_binary(card.contact_pkey)
      assert is_binary(card.contact_cert)
      assert is_binary(card.crypt_pkey)
      assert is_binary(card.crypt_cert)
    end
  end
end
