defmodule Chat.PhoenixSyncReinit do
  @moduledoc """
  Reinitializes Phoenix.Sync when the database/repo changes.

  This is needed because Electric's embedded stack is started once at application
  startup with a specific repo configuration. When the repo switches (e.g., USB
  drive ejected), the Electric stack becomes invalid because it's still connected
  to the old (now dead) database.

  This module provides a way to restart the Electric stack with the new repo
  configuration.
  """

  require Logger

  @doc """
  Reinitializes Phoenix.Sync with the current repo configuration.

  Call this after switching the Chat.Repo to point to a different database.
  It will:
  1. Stop the current Electric.StackSupervisor
  2. Update phoenix_sync config with connection opts from the current active repo
  3. Restart the Electric stack

  Returns :ok on success, {:error, reason} on failure.
  """
  def reinit do
    Logger.info("[PhoenixSyncReinit] Reinitializing Phoenix.Sync")

    with :ok <- stop_electric_stack(),
         :ok <- update_config(),
         :ok <- start_electric_stack() do
      Logger.info("[PhoenixSyncReinit] Phoenix.Sync reinitialized successfully")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("[PhoenixSyncReinit] Failed to reinitialize: #{inspect(reason)}")
        error
    end
  end

  defp stop_electric_stack do
    # Electric.StackSupervisor is started with name Electric.StackSupervisor
    # First terminate the process if running
    case Process.whereis(Electric.StackSupervisor) do
      nil ->
        Logger.debug("[PhoenixSyncReinit] Electric.StackSupervisor not running")

      pid when is_pid(pid) ->
        Logger.debug("[PhoenixSyncReinit] Stopping Electric.StackSupervisor")

        case Supervisor.terminate_child(Phoenix.Sync.Supervisor, Electric.StackSupervisor) do
          :ok ->
            :ok

          {:error, :not_found} ->
            # Try direct termination if not under Phoenix.Sync.Supervisor
            Supervisor.stop(pid, :normal)
        end
    end

    # Always try to delete the child spec (it may exist even if process isn't running)
    # This handles the case where Electric failed to start at boot
    _ = Supervisor.delete_child(Phoenix.Sync.Supervisor, Electric.StackSupervisor)
    :ok
  rescue
    e ->
      Logger.warning("[PhoenixSyncReinit] Error stopping Electric stack: #{inspect(e)}")
      :ok
  end

  defp update_config do
    # Get the current active repo and extract its runtime configuration
    current_repo = Application.get_env(:chat, :repo, Chat.Repo)

    # Get the actual runtime config from the running repo process
    # This includes any dynamic port changes made at startup
    connection_opts = get_runtime_connection_opts(current_repo)

    Logger.debug(
      "[PhoenixSyncReinit] Updating config with connection_opts: #{inspect(connection_opts)}"
    )

    # Update phoenix_sync to use connection_opts instead of repo
    # This ensures we use the actual runtime connection parameters
    current_config = Application.get_all_env(:phoenix_sync)

    new_config =
      current_config
      |> Keyword.delete(:repo)
      |> Keyword.put(:connection_opts, connection_opts)

    Enum.each(new_config, fn {key, value} ->
      Application.put_env(:phoenix_sync, key, value)
    end)

    :ok
  end

  defp get_runtime_connection_opts(repo) do
    # Try to get the runtime config from the repo's Ecto adapter
    # This reflects the actual connection parameters being used
    %{opts: opts} = Ecto.Adapter.lookup_meta(repo)

    build_connection_opts(opts)
  rescue
    _ ->
      # Fallback to static config if runtime lookup fails
      Logger.warning("[PhoenixSyncReinit] Could not get runtime config, using static config")
      get_static_connection_opts(repo)
  end

  defp get_static_connection_opts(repo) do
    config = repo.config()

    build_connection_opts(config)
  end

  defp build_connection_opts(source) do
    [
      hostname: source[:hostname] || "localhost",
      port: source[:port] || 5432,
      database: source[:database],
      username: source[:username],
      password: source[:password],
      socket_options: [{:keepalive, true}]
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp start_electric_stack do
    with {:ok, children} <- Phoenix.Sync.Application.children() do
      Enum.reduce_while(children, :ok, &start_child_step/2)
    end
  end

  defp start_child_step(child_spec, _acc) do
    case start_or_restart_child(child_spec) do
      :ok ->
        {:cont, :ok}

      {:error, reason} = err ->
        Logger.error(
          "[PhoenixSyncReinit] Failed to start child #{inspect(child_spec)}: #{inspect(reason)}"
        )

        {:halt, err}
    end
  end

  defp start_or_restart_child(child_spec) do
    case Supervisor.start_child(Phoenix.Sync.Supervisor, child_spec) do
      {:ok, _pid} ->
        :ok

      {:ok, _pid, _info} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, :already_present} ->
        # Child spec exists but process not running - delete and re-add
        _ = Supervisor.delete_child(Phoenix.Sync.Supervisor, child_id(child_spec))
        start_or_restart_child(child_spec)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp child_id(%{id: id}), do: id
  defp child_id({module, _opts}), do: module
  defp child_id(module) when is_atom(module), do: module
end
