defmodule ChatSupport.Mocks.Storage.DefaultElectricMock do
  @moduledoc """
  Stand-in for `Chat.Storage.Default.Electric` in `Chat.Storage.Default` tests.

  Each call is sent to the pid in `:default_electric_mock_pid` app env as
  `{:electric, call}`, with the Default unit and repo seen at that moment.
  """

  alias Chat.Storage.Default

  def stop, do: report(:stop)
  def release(unit), do: report({:release, unit.id})
  def start(unit), do: report({:start, unit.id})

  defp report(call) do
    case Application.get_env(:chat, :default_electric_mock_pid) do
      nil -> :ok
      pid -> send(pid, {:electric, call, Default.unit().id, Chat.Db.repo()})
    end

    :ok
  end
end

defmodule ChatSupport.Mocks.Storage.DbBrokersMock do
  @moduledoc "No-op `Chat.Sync.DbBrokers` for `Chat.Storage.Default` tests: the switched-to CubDB is not running."
  def refresh, do: :ok
end
