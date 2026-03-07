defmodule ChatSupport.Mocks.PhoenixSync.ApplicationMock do
  @moduledoc """
  Mock for Phoenix.Sync.Application used in PhoenixSyncReinit tests.

  Rewire replaces Phoenix.Sync.Application with this module, but because
  `Application` is a trailing component of that module name, Rewire also
  replaces bare `Application.*` calls in the rewired module. Those calls are
  delegated back to the real Application module here.

  `children/0` is the only function that actually needs a mock — it returns
  whatever is configured via `:phoenix_sync_children_mock` in Application env.
  """

  defdelegate get_env(app, key, default), to: Application
  defdelegate get_all_env(app), to: Application
  defdelegate put_env(app, key, value), to: Application

  def children do
    Application.get_env(:chat, :phoenix_sync_children_mock, {:ok, []})
  end
end
