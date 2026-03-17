defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.DbMock do
  @moduledoc """
  Mock for Chat.Db used in ShapeConsumer tests.

  Returns repo readiness state from Application env under
  `:consumer_test_repo_ready`. Defaults to true.
  """

  def repo_ready? do
    Application.get_env(:chat, :consumer_test_repo_ready, true)
  end
end
