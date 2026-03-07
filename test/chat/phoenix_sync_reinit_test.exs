defmodule Chat.PhoenixSyncReinitTest do
  use ExUnit.Case, async: false

  import Rewire

  alias Chat.PhoenixSyncReinit

  rewire(PhoenixSyncReinit, [
    {Phoenix.Sync.Application, ChatSupport.Mocks.PhoenixSync.ApplicationMock}
  ])

  setup do
    original_config = :application.get_all_env(:phoenix_sync)

    on_exit(fn ->
      Enum.each(:application.get_all_env(:phoenix_sync), fn {k, _} ->
        :application.unset_env(:phoenix_sync, k)
      end)

      Enum.each(original_config, fn {k, v} ->
        :application.set_env(:phoenix_sync, k, v)
      end)

      :application.unset_env(:chat, :phoenix_sync_children_mock)
    end)

    :ok
  end

  describe "reinit/0 - success path" do
    test "returns :ok when Electric stack reinitializes successfully" do
      :application.set_env(:chat, :phoenix_sync_children_mock, {:ok, []})

      assert :ok = PhoenixSyncReinit.reinit()
    end

    test "sets :connection_opts in phoenix_sync config" do
      :application.set_env(:phoenix_sync, :repo, Chat.Repo)
      :application.set_env(:chat, :phoenix_sync_children_mock, {:ok, []})

      :ok = PhoenixSyncReinit.reinit()

      {:ok, opts} = :application.get_env(:phoenix_sync, :connection_opts)
      assert is_list(opts)
      assert Keyword.has_key?(opts, :hostname)
    end

    test "connection_opts hostname defaults to localhost when not explicitly set" do
      :application.set_env(:chat, :phoenix_sync_children_mock, {:ok, []})

      :ok = PhoenixSyncReinit.reinit()

      {:ok, opts} = :application.get_env(:phoenix_sync, :connection_opts)
      assert opts[:hostname] != nil
    end

    test "preserves other phoenix_sync config keys during update" do
      :application.set_env(:phoenix_sync, :some_other_key, "some_value")
      :application.set_env(:chat, :phoenix_sync_children_mock, {:ok, []})

      :ok = PhoenixSyncReinit.reinit()

      assert {:ok, "some_value"} = :application.get_env(:phoenix_sync, :some_other_key)
    end
  end

  describe "reinit/0 - error path" do
    test "propagates error when Phoenix.Sync.Application.children/0 returns error" do
      :application.set_env(:chat, :phoenix_sync_children_mock, {:error, :config_error})

      assert {:error, :config_error} = PhoenixSyncReinit.reinit()
    end

    test "propagates arbitrary error reasons" do
      :application.set_env(:chat, :phoenix_sync_children_mock, {:error, :missing_connection})

      assert {:error, :missing_connection} = PhoenixSyncReinit.reinit()
    end
  end

  describe "reinit/0 - resilience" do
    test "succeeds even when Electric.StackSupervisor is not running" do
      # Electric.StackSupervisor is not started in test env;
      # stop_electric_stack must handle this gracefully via rescue
      :application.set_env(:chat, :phoenix_sync_children_mock, {:ok, []})

      assert :ok = PhoenixSyncReinit.reinit()
    end

    test "succeeds even when Phoenix.Sync.Supervisor is not running" do
      # Supervisor.delete_child raises when supervisor not found;
      # the rescue block in stop_electric_stack must catch it
      :application.set_env(:chat, :phoenix_sync_children_mock, {:ok, []})

      assert :ok = PhoenixSyncReinit.reinit()
    end
  end
end
