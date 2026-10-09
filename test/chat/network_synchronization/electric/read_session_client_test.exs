defmodule Chat.NetworkSynchronization.Electric.ReadSessionClientTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers
  import Rewire

  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ReadSessionClient
  alias Chat.Pq.ReadSession
  alias ChatSupport.Mocks.NetworkSynchronization.Electric.ServerIdentityMock

  rewire(ReadSessionClient, [
    {Req, ChatSupport.Mocks.NetworkSynchronization.Electric.EndpointReqMock},
    {Chat.Pq.ServerIdentity, ServerIdentityMock}
  ])

  @peer_url "http://peer.local"

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    {owner, owner_card} = identity_with_card("Owner")
    put_gate(:trust, owner_card)

    %{owner: owner, owner_card: owner_card}
  end

  test "vouched server identity gets a token for the shape", %{
    owner: owner,
    owner_card: owner_card
  } do
    %{user_hash: server_hash} = act_as_server_with_card()
    vouch(owner, owner_card.user_hash, server_hash, "storage.read")

    assert {:ok, token, 300} = ReadSessionClient.open(@peer_url, :dialog_messages)

    assert {:ok, %{shape: :dialog_messages, user_hash: ^server_hash}} =
             ReadSession.lookup(token)
  end

  test "unvouched server identity is not in trust chain" do
    act_as_server_with_card()

    assert {:error, :not_in_trust_chain} = ReadSessionClient.open(@peer_url, :user_card)
  end

  test "server identity without a card on the peer is unknown" do
    ServerIdentityMock.put(User.generate_pq_identity("Server"))

    assert {:error, :unknown_user} = ReadSessionClient.open(@peer_url, :user_card)
  end

  test "unknown shape is an http error" do
    act_as_server_with_card()

    assert {:error, {:http, 400, %{"error" => "unknown_shape"}}} =
             ReadSessionClient.open(@peer_url, :no_such_shape)
  end

  defp act_as_server_with_card do
    {server, server_card} = identity_with_card("Server")
    ServerIdentityMock.put(server)
    server_card
  end
end
