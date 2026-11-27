defmodule Chat.Data.Shapes.UserStorageSyncTest do
  @moduledoc """
  Peer-sync callbacks of the `user_storage` shape, called directly (the way
  `ShapeWriter` does): unsigned rows pass derivation untouched, unknown
  updates are skipped and forged updates are dropped with a warning.
  """
  use ChatWeb.DataCase, async: true

  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1, sign_with_hash: 3]
  import ExUnit.CaptureLog

  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Shapes
  alias Chat.Data.Types.UserStorageSignHash
  alias Chat.Data.User

  setup do
    identity = User.generate_pq_identity("Owner")
    card = insert_user_card(identity)

    {:ok, identity: identity, user_hash: card.user_hash}
  end

  test "sync_derive_fields/1 leaves an unsigned row untouched" do
    storage = %UserStorage{sign_b64: nil, sign_hash: nil}

    assert Shapes.UserStorage.sync_derive_fields(storage) == storage
  end

  describe "sync_persist(:update, _)" do
    test "skips an update for an unknown storage row", %{identity: identity, user_hash: user_hash} do
      storage = signed_storage(identity, user_hash, Ecto.UUID.generate(), 1000)

      assert {:ok, ^storage} = Shapes.UserStorage.sync_persist(:update, storage)
      refute User.get_storage(user_hash, storage.uuid)
    end

    test "drops an update with a forged signature", %{identity: identity, user_hash: user_hash} do
      v1 = signed_storage(identity, user_hash, Ecto.UUID.generate(), 1000)
      {:ok, _} = Shapes.UserStorage.sync_persist(:insert, v1)

      forged =
        identity
        |> signed_storage(user_hash, v1.uuid, 2000)
        |> Map.put(:value_b64, "tampered")

      log =
        capture_log(fn ->
          assert {:ok, ^forged} = Shapes.UserStorage.sync_persist(:update, forged)
        end)

      assert log =~ "Invalid user_storage update signature"
      assert %{value_b64: "v1000"} = User.get_storage(user_hash, v1.uuid)
    end
  end

  # Helpers

  defp signed_storage(identity, user_hash, uuid, ts) do
    %UserStorage{
      user_hash: user_hash,
      uuid: uuid,
      value_b64: "v#{ts}",
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: ts
    }
    |> sign_with_hash(identity.sign_skey, &UserStorageSignHash.from_binary/1)
  end
end
