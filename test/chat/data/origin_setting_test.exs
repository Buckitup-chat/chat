defmodule Chat.Data.OriginSettingTest do
  use ChatWeb.DataCase

  alias Chat.Data.OriginSetting
  alias Chat.Data.Schemas.OriginSetting, as: OriginSettingSchema

  alias Chat.Data.User

  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1, insert_origin: 2]

  setup do
    origin_identity = User.generate_pq_identity("TestOrigin")
    owner = User.generate_pq_identity("TestOwner")
    insert_user_card(origin_identity)
    insert_user_card(owner)
    origin = insert_origin(origin_identity, owner)
    %{origin_hash: origin.origin_hash}
  end

  describe "get_review_token_ttl_days/1" do
    test "defaults to 7 when no setting exists", %{origin_hash: origin_hash} do
      assert OriginSetting.get_review_token_ttl_days(origin_hash) == 7
    end

    test "returns stored value", %{origin_hash: origin_hash} do
      insert_setting(origin_hash, "review_token_ttl_days", "14")
      assert OriginSetting.get_review_token_ttl_days(origin_hash) == 14
    end

    test "defaults to 7 when setting is soft-deleted", %{origin_hash: origin_hash} do
      insert_setting(origin_hash, "review_token_ttl_days", "14", deleted_flag: true)
      assert OriginSetting.get_review_token_ttl_days(origin_hash) == 7
    end

    test "defaults to 7 when stored value is not a valid integer", %{origin_hash: origin_hash} do
      insert_setting(origin_hash, "review_token_ttl_days", "abc")
      assert OriginSetting.get_review_token_ttl_days(origin_hash) == 7
    end
  end

  describe "review_token_ttl_days validation" do
    test "accepts valid integer string" do
      assert build_changeset("review_token_ttl_days", "7").valid?
    end

    test "accepts boundary values" do
      assert build_changeset("review_token_ttl_days", "1").valid?
      assert build_changeset("review_token_ttl_days", "365").valid?
    end

    test "rejects zero" do
      refute build_changeset("review_token_ttl_days", "0").valid?
    end

    test "rejects negative" do
      refute build_changeset("review_token_ttl_days", "-1").valid?
    end

    test "rejects non-integer string" do
      refute build_changeset("review_token_ttl_days", "abc").valid?
    end

    test "rejects value above 365" do
      refute build_changeset("review_token_ttl_days", "366").valid?
    end

    test "rejects float string" do
      refute build_changeset("review_token_ttl_days", "7.5").valid?
    end
  end

  defp build_changeset(key, value) do
    origin_hash = "u_" <> String.duplicate("aa", 64)

    OriginSettingSchema.create_changeset(%OriginSettingSchema{}, %{
      origin_hash: origin_hash,
      key: key,
      value: value,
      deleted_flag: false,
      owner_timestamp: 1,
      sign_b64: <<0::256>>
    })
  end

  defp insert_setting(origin_hash, key, value, opts \\ []) do
    deleted = Keyword.get(opts, :deleted_flag, false)

    Repo.insert!(%OriginSettingSchema{
      origin_hash: origin_hash,
      key: key,
      value: value,
      deleted_flag: deleted,
      owner_timestamp: 1,
      sign_b64: <<0::256>>
    })
  end
end
