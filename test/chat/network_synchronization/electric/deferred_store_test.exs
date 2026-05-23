defmodule Chat.NetworkSynchronization.Electric.DeferredStoreTest do
  use ExUnit.Case, async: true, group: :ets_deferred

  alias Chat.NetworkSynchronization.Electric.DeferredStore

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)
    :ok
  end

  describe "defer/5 and check_children/2" do
    test "stores a record and retrieves it by parent" do
      defer_storage("hash1", "uuid1", "http://peer1:4444")

      assert [record] = DeferredStore.check_children(:user_card, "hash1")
      assert record.shape == :user_storage
      assert record.key == [user_hash: "hash1", uuid: "uuid1"]
      assert record.operation == :insert
      assert record.missing_parents == [{:user_card, "hash1"}]
      assert record.peer_url == "http://peer1:4444"
    end

    test "check_children removes the record from the store" do
      defer_storage("hash1", "uuid1", "http://peer1:4444")

      assert [_] = DeferredStore.check_children(:user_card, "hash1")
      assert [] = DeferredStore.check_children(:user_card, "hash1")
    end

    test "returns empty list when no match" do
      assert [] = DeferredStore.check_children(:user_card, "nonexistent")
    end

    test "multiple records waiting on the same parent" do
      defer_storage("hash1", "uuid1", "http://peer1:4444")
      defer_storage("hash1", "uuid2", "http://peer2:4444")

      assert length(DeferredStore.check_children(:user_card, "hash1")) == 2
    end
  end

  describe "purge_peer/1" do
    test "removes all records for a peer" do
      defer_storage("h1", "u1", "http://peer1:4444")
      defer_storage("h2", "u2", "http://peer2:4444")

      DeferredStore.purge_peer("http://peer1:4444")

      assert [] = DeferredStore.check_children(:user_card, "h1")
      assert [_] = DeferredStore.check_children(:user_card, "h2")
    end
  end

  describe "purge_shape/2" do
    test "removes records for a specific peer+shape" do
      defer_storage("h1", "u1", "http://peer1:4444")
      defer_shape(:dialog_keys, [sender_hash: "h2"], [{:user_card, "h2"}], "http://peer1:4444")

      DeferredStore.purge_shape("http://peer1:4444", :user_storage)

      assert [] = DeferredStore.check_children(:user_card, "h1")
      assert [_] = DeferredStore.check_children(:user_card, "h2")
    end
  end

  describe "TTL sweep" do
    test "purges expired records" do
      insert_expired_record("h1", "u1", "http://peer1:4444")

      trigger_ttl_sweep()

      assert [] = DeferredStore.check_children(:user_card, "h1")
    end

    test "keeps non-expired records" do
      defer_storage("h1", "u1", "http://peer1:4444")

      trigger_ttl_sweep()

      assert [_] = DeferredStore.check_children(:user_card, "h1")
    end
  end

  # Helpers

  defp defer_storage(user_hash, uuid, peer_url) do
    DeferredStore.defer(
      :user_storage,
      [user_hash: user_hash, uuid: uuid],
      :insert,
      [{:user_card, user_hash}],
      peer_url
    )
  end

  defp defer_shape(shape, key, missing_parents, peer_url) do
    DeferredStore.defer(shape, key, :insert, missing_parents, peer_url)
  end

  defp insert_expired_record(user_hash, uuid, peer_url) do
    record = %Chat.NetworkSynchronization.Electric.DeferredRecord{
      shape: :user_storage,
      key: [user_hash: user_hash, uuid: uuid],
      operation: :insert,
      missing_parents: [{:user_card, user_hash}],
      peer_url: peer_url,
      deferred_at: System.monotonic_time(:millisecond) - :timer.hours(3)
    }

    :ets.insert(:buckitup_deferred_records, {{:user_card, user_hash}, record})
  end

  defp trigger_ttl_sweep do
    send(Process.whereis(DeferredStore), :ttl_sweep)
    Process.sleep(50)
  end
end
