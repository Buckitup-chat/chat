defmodule Chat.NetworkSynchronization.Electric.OffsetStoreTest do
  use ExUnit.Case, async: false

  alias Chat.NetworkSynchronization.Electric.OffsetStore

  @peer_url "http://192.168.1.99"
  @resume %{shape_handle: "abc123", offset: "some/0", schema: %{}}

  setup do
    OffsetStore.delete(@peer_url)
    on_exit(fn -> OffsetStore.delete(@peer_url) end)
    :ok
  end

  test "save persists and load retrieves resume message" do
    OffsetStore.save(@peer_url, :user_card, @resume)

    assert OffsetStore.load(@peer_url, :user_card) == @resume
  end

  test "load returns nil when nothing saved" do
    assert OffsetStore.load(@peer_url, :user_card) == nil
    assert OffsetStore.load(@peer_url, :user_storage) == nil
  end

  test "save and load are shape-scoped" do
    resume_card = %{shape_handle: "card_handle", offset: "0/1", schema: %{}}
    resume_storage = %{shape_handle: "storage_handle", offset: "0/2", schema: %{}}

    OffsetStore.save(@peer_url, :user_card, resume_card)
    OffsetStore.save(@peer_url, :user_storage, resume_storage)

    assert OffsetStore.load(@peer_url, :user_card) == resume_card
    assert OffsetStore.load(@peer_url, :user_storage) == resume_storage
  end

  test "delete removes all shape offsets for a peer" do
    OffsetStore.save(@peer_url, :user_card, @resume)
    OffsetStore.save(@peer_url, :user_storage, @resume)

    OffsetStore.delete(@peer_url)

    assert OffsetStore.load(@peer_url, :user_card) == nil
    assert OffsetStore.load(@peer_url, :user_storage) == nil
  end

  test "delete does not affect other peers" do
    other_peer = "http://192.168.1.100"

    OffsetStore.save(@peer_url, :user_card, @resume)
    OffsetStore.save(other_peer, :user_card, @resume)

    OffsetStore.delete(@peer_url)

    assert OffsetStore.load(@peer_url, :user_card) == nil
    assert OffsetStore.load(other_peer, :user_card) == @resume

    OffsetStore.delete(other_peer)
  end
end
