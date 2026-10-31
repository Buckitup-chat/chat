defmodule ChatWeb.ElectricLive.ModerationSandboxLive.SettingsClientTest do
  @moduledoc "Pure payload construction for origin settings insert/update."
  use ExUnit.Case, async: true

  alias ChatWeb.ElectricLive.ModerationSandboxLive.SettingsClient

  @origin_hash "u_" <> String.duplicate("a", 128)

  setup do
    {_sign_pkey, sign_skey} = EnigmaPq.generate_sign_keypair()
    %{sign_skey: sign_skey}
  end

  describe "build_set_payload/5" do
    test "produces an insert mutation for a new setting", %{sign_skey: skey} do
      mutation =
        SettingsClient.build_set_payload(@origin_hash, "review_access", "open", nil, skey)

      assert mutation["type"] == "insert"
      assert mutation["modified"]["origin_hash"] == @origin_hash
      assert mutation["modified"]["key"] == "review_access"
      assert mutation["modified"]["value"] == "open"
      assert mutation["modified"]["deleted_flag"] == false
      assert is_integer(mutation["modified"]["owner_timestamp"])
      assert mutation["syncMetadata"] == %{"relation" => "origin_settings"}
    end

    test "produces an update mutation for an existing setting", %{sign_skey: skey} do
      existing = %{
        key: "review_access",
        value: "open",
        owner_timestamp: 1000,
        deleted_flag: false
      }

      mutation =
        SettingsClient.build_set_payload(
          @origin_hash,
          "review_access",
          "invite_only",
          existing,
          skey
        )

      assert mutation["type"] == "update"
      assert mutation["original"] == %{"origin_hash" => @origin_hash, "key" => "review_access"}
      assert mutation["changes"]["value"] == "invite_only"
      assert mutation["changes"]["deleted_flag"] == false
    end

    test "bumps timestamp above existing on update", %{sign_skey: skey} do
      ts = Chat.TimeKeeper.now_unix() + 1_000_000
      existing = %{key: "review_greeting", value: "old", owner_timestamp: ts, deleted_flag: false}

      mutation =
        SettingsClient.build_set_payload(@origin_hash, "review_greeting", "new", existing, skey)

      assert mutation["changes"]["owner_timestamp"] >= ts + 1
    end

    test "insert timestamp uses now_unix", %{sign_skey: skey} do
      before = Chat.TimeKeeper.now_unix()

      mutation =
        SettingsClient.build_set_payload(@origin_hash, "review_greeting", "hi", nil, skey)

      assert mutation["modified"]["owner_timestamp"] >= before
    end
  end
end
