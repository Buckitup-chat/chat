defmodule Chat.Data.Schemas.VouchTokenTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.Schemas.VouchToken

  @valid_attrs %{
    kind: "device.BK-001.storage.write",
    issuer_hash: "u_" <> String.duplicate("ab", 64),
    subject_hash: "u_" <> String.duplicate("cd", 64),
    owner_timestamp: 1_000_000,
    deleted_flag: false,
    sign_b64: :crypto.strong_rand_bytes(64)
  }

  describe "create_changeset/2" do
    test "valid attrs produce a valid changeset" do
      cs = VouchToken.create_changeset(%VouchToken{}, @valid_attrs)
      assert cs.valid?
    end

    test "requires all fields" do
      cs = VouchToken.create_changeset(%VouchToken{}, %{})
      refute cs.valid?

      for field <- [:kind, :issuer_hash, :subject_hash, :owner_timestamp, :sign_b64] do
        assert Keyword.has_key?(cs.errors, field), "expected error on #{field}"
      end
    end
  end

  describe "update_changeset/2" do
    test "valid update attrs produce a valid changeset" do
      existing = struct(VouchToken, @valid_attrs)

      cs =
        VouchToken.update_changeset(existing, %{
          deleted_flag: true,
          owner_timestamp: 2_000_000,
          sign_b64: :crypto.strong_rand_bytes(64)
        })

      assert cs.valid?
    end

    test "requires update fields" do
      existing = struct(VouchToken, @valid_attrs)

      cs =
        VouchToken.update_changeset(existing, %{
          deleted_flag: nil,
          owner_timestamp: nil,
          sign_b64: nil
        })

      refute cs.valid?

      for field <- [:deleted_flag, :owner_timestamp, :sign_b64] do
        assert Keyword.has_key?(cs.errors, field), "expected error on #{field}"
      end
    end
  end
end
