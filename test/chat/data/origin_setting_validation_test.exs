defmodule Chat.Data.OriginSettingValidationTest do
  @moduledoc "Validation tests for origin setting insert/update (signature, timestamp, auth)."
  use ChatWeb.DataCase, async: true

  import Chat.Test.ReviewFixtures, only: [insert_origin: 2, insert_user_card: 1, sign_with_key: 2]

  alias Chat.Data.OriginSetting.Validation
  alias Chat.Data.Schemas.OriginSetting
  alias Chat.Data.User
  alias Phoenix.Sync.Writer.Operation

  setup do
    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")
    stranger = User.generate_pq_identity("Stranger")

    insert_user_card(owner)
    insert_user_card(origin_identity)
    insert_user_card(stranger)
    insert_origin(origin_identity, owner)

    {:ok,
     owner: owner,
     origin_identity: origin_identity,
     stranger: stranger,
     origin_hash: User.extract_pq_card(origin_identity).user_hash}
  end

  describe "validate_origin_setting_insert/1" do
    test "accepts a setting signed by origin identity", ctx do
      changeset = ctx |> build_setting() |> Validation.validate_origin_setting_insert()
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "rejects a setting signed by a stranger", ctx do
      changeset =
        ctx
        |> build_setting(signer: ctx.stranger)
        |> Validation.validate_origin_setting_insert()

      assert_sign_error(changeset)
    end

    test "rejects a forged signature", ctx do
      changeset =
        ctx
        |> build_setting()
        |> Map.put(:sign_b64, :crypto.strong_rand_bytes(64))
        |> Validation.validate_origin_setting_insert()

      assert_sign_error(changeset)
    end

    test "rejects an invalid value", ctx do
      changeset =
        ctx
        |> build_setting(value: "everyone")
        |> Validation.validate_origin_setting_insert()

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :value)
    end
  end

  describe "validate_origin_setting_update/2" do
    test "accepts a newer update signed by origin identity", ctx do
      existing = insert_setting(ctx)
      updated = build_update(existing, ctx.origin_identity, value: "open")

      changeset = Validation.validate_origin_setting_update(existing, updated)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "accepts a newer update signed by origin owner", ctx do
      existing = insert_setting(ctx)
      updated = build_update(existing, ctx.owner, value: "open")

      changeset = Validation.validate_origin_setting_update(existing, updated)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "rejects an update signed by a stranger", ctx do
      existing = insert_setting(ctx)
      updated = build_update(existing, ctx.stranger, value: "open")

      existing
      |> Validation.validate_origin_setting_update(updated)
      |> assert_sign_error()
    end

    test "rejects a stale update", ctx do
      existing = insert_setting(ctx, owner_timestamp: 2000)
      updated = build_update(existing, ctx.origin_identity, owner_timestamp: 1000)

      refute Validation.validate_origin_setting_update(existing, updated).valid?
    end

    test "rejects an invalid value", ctx do
      existing = insert_setting(ctx)
      updated = build_update(existing, ctx.origin_identity, value: "everyone")

      changeset = Validation.validate_origin_setting_update(existing, updated)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :value)
    end

    test "nil fields keep the existing values", ctx do
      existing = insert_setting(ctx)
      updated = existing |> build_update(ctx.origin_identity) |> Map.put(:value, nil)

      changeset = Validation.validate_origin_setting_update(existing, updated)
      assert Ecto.Changeset.get_field(changeset, :value) == "invite_only"
    end
  end

  describe "origin_setting_validate/3" do
    test ":insert checks the signature", ctx do
      good = ctx |> build_setting() |> Map.from_struct()
      bad = ctx |> build_setting(signer: ctx.stranger) |> Map.from_struct()

      assert Validation.origin_setting_validate(%OriginSetting{}, good, :insert).valid?
      assert_sign_error(Validation.origin_setting_validate(%OriginSetting{}, bad, :insert))
    end

    test ":update checks signature and timestamp", ctx do
      existing = insert_setting(ctx, owner_timestamp: 2000)
      newer = existing |> build_update(ctx.owner, value: "open") |> update_changes()
      stale = existing |> build_update(ctx.owner, owner_timestamp: 1000) |> update_changes()
      forged = existing |> build_update(ctx.stranger, value: "open") |> update_changes()

      assert Validation.origin_setting_validate(existing, newer, :update).valid?
      refute Validation.origin_setting_validate(existing, stale, :update).valid?
      assert_sign_error(Validation.origin_setting_validate(existing, forged, :update))
    end
  end

  defp update_changes(setting) do
    setting
    |> Map.from_struct()
    |> Map.take([:value, :deleted_flag, :owner_timestamp, :sign_b64])
  end

  describe "origin_setting_allowed/2" do
    test "accepts insert PoP signed by origin identity or owner", ctx do
      operation = insert_operation(ctx.origin_hash)

      assert :ok =
               Validation.origin_setting_allowed(operation, sign_challenge(ctx.origin_identity))

      assert :ok = Validation.origin_setting_allowed(operation, sign_challenge(ctx.owner))
    end

    test "accepts insert with atom-keyed changes", ctx do
      operation = %{insert_operation(ctx.origin_hash) | changes: %{origin_hash: ctx.origin_hash}}
      assert :ok = Validation.origin_setting_allowed(operation, sign_challenge(ctx.owner))
    end

    test "accepts update PoP signed by origin identity", ctx do
      operation = update_operation(ctx.origin_hash)

      assert :ok =
               Validation.origin_setting_allowed(operation, sign_challenge(ctx.origin_identity))
    end

    test "rejects PoP signed by a stranger", ctx do
      assert {:error, "Invalid operation"} =
               ctx.origin_hash
               |> insert_operation()
               |> Validation.origin_setting_allowed(sign_challenge(ctx.stranger))

      assert {:error, "Invalid operation"} =
               ctx.origin_hash
               |> update_operation()
               |> Validation.origin_setting_allowed(sign_challenge(ctx.stranger))
    end

    test "rejects an unknown origin", ctx do
      unknown_hash =
        User.generate_pq_identity("Nowhere") |> User.extract_pq_card() |> Map.get(:user_hash)

      assert {:error, "Invalid operation"} =
               unknown_hash
               |> insert_operation()
               |> Validation.origin_setting_allowed(sign_challenge(ctx.owner))
    end
  end

  defp insert_operation(origin_hash) do
    %Operation{
      index: 0,
      operation: :insert,
      relation: "origin_settings",
      data: nil,
      changes: %{"origin_hash" => origin_hash, "key" => "review_access"}
    }
  end

  defp update_operation(origin_hash) do
    %Operation{
      index: 0,
      operation: :update,
      relation: "origin_settings",
      data: %{"origin_hash" => origin_hash, "key" => "review_access"},
      changes: %{"value" => "open"}
    }
  end

  defp sign_challenge(identity) do
    challenge = :crypto.strong_rand_bytes(32)
    signature = :crypto.sign(:mldsa87, :none, challenge, identity.sign_skey)
    %{challenge: challenge, signature: signature}
  end

  # Helpers

  defp assert_sign_error(changeset) do
    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :sign_b64)
  end

  defp build_setting(ctx, opts \\ []) do
    signer = Keyword.get(opts, :signer, ctx.origin_identity)

    %OriginSetting{
      origin_hash: ctx.origin_hash,
      key: "review_access",
      value: Keyword.get(opts, :value, "invite_only"),
      deleted_flag: false,
      owner_timestamp: Keyword.get(opts, :owner_timestamp, System.os_time(:millisecond))
    }
    |> sign_with_key(signer.sign_skey)
  end

  defp insert_setting(ctx, opts \\ []) do
    ctx
    |> build_setting(opts)
    |> Map.from_struct()
    |> then(&OriginSetting.create_changeset(%OriginSetting{}, &1))
    |> Repo.insert!()
  end

  defp build_update(existing, signer, opts \\ []) do
    value = Keyword.get(opts, :value, existing.value)
    owner_timestamp = Keyword.get(opts, :owner_timestamp, existing.owner_timestamp + 1)

    %{existing | value: value, owner_timestamp: owner_timestamp}
    |> sign_with_key(signer.sign_skey)
  end
end
