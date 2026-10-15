defmodule Chat.NetworkSynchronization.Electric.SyncBotCardPusherTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers, only: [identity_with_card: 1, put_gate: 2]
  import Rewire

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.SyncBotCardPusher
  alias Chat.Repo
  alias ChatSupport.Mocks.NetworkSynchronization.Electric.ServerIdentityMock

  rewire(SyncBotCardPusher, [
    {Req, ChatSupport.Mocks.NetworkSynchronization.Electric.EndpointReqMock},
    {Chat.Pq.ServerIdentity, ServerIdentityMock}
  ])

  @peer_url "http://peer.local"

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)
    :ok
  end

  test "pushes SyncBot card to peer and card appears in the database" do
    identity = put_server_identity()
    expected_hash = ServerIdentityMock.user_hash()
    expected_sign_pkey = identity.sign_pkey

    assert :ok = SyncBotCardPusher.push(@peer_url)

    assert %UserCard{
             user_hash: ^expected_hash,
             sign_pkey: ^expected_sign_pkey,
             name: "SyncBot_" <> _,
             deleted_flag: false
           } = card = Repo.get(UserCard, expected_hash)

    assert User.valid_card?(card)
  end

  test "push is idempotent — second push succeeds without error" do
    put_server_identity()

    assert :ok = SyncBotCardPusher.push(@peer_url)
    assert :ok = SyncBotCardPusher.push(@peer_url)
  end

  test "push succeeds even in trust mode (user_card is never chain-gated)" do
    {_owner, owner_card} = identity_with_card("Owner")
    put_gate(:trust, owner_card)

    put_server_identity()

    assert :ok = SyncBotCardPusher.push(@peer_url)

    assert %UserCard{} = Repo.get(UserCard, ServerIdentityMock.user_hash())
  end

  defp put_server_identity do
    identity = User.generate_pq_identity("SyncBot_test")
    ServerIdentityMock.put(identity)
    identity
  end
end
