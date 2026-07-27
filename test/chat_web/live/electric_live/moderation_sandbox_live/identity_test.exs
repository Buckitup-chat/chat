defmodule ChatWeb.ElectricLive.ModerationSandboxLive.IdentityTest do
  @moduledoc """
  Import of the origin identity export and its proof against the origin's
  published `user_cards` row.
  """
  use ExUnit.Case, async: true

  alias Chat.Data.Schemas.UserCard
  alias ChatWeb.ElectricLive.ModerationSandboxLive.Identity
  alias EnigmaPq

  @origin_hash "u_" <> String.duplicate("a", 128)

  setup do
    {sign_pkey, sign_skey} = EnigmaPq.generate_sign_keypair()
    {crypt_pkey, crypt_skey} = EnigmaPq.generate_crypt_keypair()

    %{
      keys: %{
        sign_pkey: sign_pkey,
        sign_skey: sign_skey,
        crypt_pkey: crypt_pkey,
        crypt_skey: crypt_skey
      },
      card: %UserCard{sign_pkey: to_b64(sign_pkey), crypt_pkey: to_b64(crypt_pkey)}
    }
  end

  describe "parse/1" do
    test "reads an origin identity export", ctx do
      {:ok, identity} = ctx.keys |> export_json() |> Identity.parse()

      assert identity.origin_hash == @origin_hash
      assert identity.name == "Test Coffee Shop"
      assert identity.sign_skey == ctx.keys.sign_skey
      assert identity.crypt_skey == ctx.keys.crypt_skey
    end

    test "rejects a personal identity export", ctx do
      json =
        ctx.keys |> export_json() |> replace("buckitup_origin_identity", "buckitup_pq_identity")

      assert {:error, reason} = Identity.parse(json)
      assert reason =~ "not an origin identity export"
    end

    test "rejects an export missing a key", ctx do
      json = ctx.keys |> export_json() |> replace("crypt_skey", "unused_field")

      assert Identity.parse(json) == {:error, "missing field: crypt_skey"}
    end

    test "rejects an export with an empty key", ctx do
      json = ctx.keys |> Map.put(:crypt_skey, "") |> export_json()

      assert Identity.parse(json) == {:error, "invalid or empty crypt_skey"}
    end

    test "rejects a file that is not JSON" do
      assert Identity.parse("<html>nope</html>") == {:error, "not valid JSON"}
    end
  end

  describe "verify_against_card/2" do
    test "accepts keys belonging to the origin card", ctx do
      {:ok, identity} = ctx.keys |> export_json() |> Identity.parse()

      assert Identity.verify_against_card(identity, ctx.card) == :ok
    end

    test "rejects a signing key from another identity", ctx do
      {_other_pkey, other_skey} = EnigmaPq.generate_sign_keypair()

      {:ok, identity} =
        ctx.keys |> Map.put(:sign_skey, other_skey) |> export_json() |> Identity.parse()

      assert {:error, reason} = Identity.verify_against_card(identity, ctx.card)
      assert reason =~ "sign_skey does not match"
    end

    test "rejects an encryption key from another identity", ctx do
      {_other_pkey, other_skey} = EnigmaPq.generate_crypt_keypair()

      {:ok, identity} =
        ctx.keys |> Map.put(:crypt_skey, other_skey) |> export_json() |> Identity.parse()

      assert {:error, reason} = Identity.verify_against_card(identity, ctx.card)
      assert reason =~ "crypt_skey does not match"
    end

    test "rejects an origin with no user_cards row", ctx do
      {:ok, identity} = ctx.keys |> export_json() |> Identity.parse()

      assert {:error, reason} = Identity.verify_against_card(identity, nil)
      assert reason =~ "no user_cards row"
    end
  end

  # Helpers

  defp export_json(keys) do
    Jason.encode!(%{
      type: "buckitup_origin_identity",
      version: 1,
      origin_hash: @origin_hash,
      name: "Test Coffee Shop",
      sign_skey: to_b64(keys.sign_skey),
      crypt_skey: to_b64(keys.crypt_skey)
    })
  end

  defp replace(json, from, to), do: String.replace(json, from, to)

  defp to_b64(binary) when is_binary(binary), do: Base.encode64(binary, padding: false)
end
