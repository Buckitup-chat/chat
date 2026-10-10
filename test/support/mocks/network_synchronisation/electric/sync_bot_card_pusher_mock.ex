defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.SyncBotCardPusherMock do
  @moduledoc "SyncBotCardPusher mock for PeerConnector tests. Notifies the test pid on push."

  def push(peer_url) do
    notify({:sync_bot_card_pushed, peer_url})
    :ok
  end

  defp notify(msg) do
    case Application.get_env(:chat, :peer_connector_test_pid) do
      pid when is_pid(pid) -> send(pid, msg)
      _ -> :ok
    end
  end
end
