defmodule Chat.Storage.Pg.LogicalReplicator.Subscription do
  @moduledoc """
  Manages PostgreSQL logical replication subscriptions.
  Provides CRUD operations for subscriptions including creation,
  enabling/disabling, and cleanup.
  """

  use Toolbox.OriginLog

  @type repo :: module()
  @type subscription_name :: String.t()

  @doc """
  Creates a subscription on the given repo to subscribe to a publication.

  The subscription will connect to the source database using the provided
  connection string and subscribe to the specified publication.

  Options:
  - `:copy_data` - whether to copy existing data (default: false, since bootstrap already copied)
  - `:enabled` - whether to enable the subscription immediately (default: true)

  ## Example

      create_subscription(
        Chat.MainRepo,
        "host=localhost port=5433 dbname=chat_internal user=replicator password=secret",
        "internal_to_main",
        "main_from_internal"
      )
  """
  @spec create_subscription(repo(), String.t(), String.t(), subscription_name(), keyword()) ::
          :ok | {:error, term()}
  def create_subscription(
        repo,
        connection_string,
        publication_name,
        subscription_name,
        opts \\ []
      ) do
    copy_data = Keyword.get(opts, :copy_data, false)
    enabled = Keyword.get(opts, :enabled, true)

    exists_sql = """
    SELECT 1 FROM pg_subscription WHERE subname = '#{subscription_name}' LIMIT 1
    """

    case repo.query(exists_sql) do
      {:ok, %{rows: [_ | _]}} ->
        :ok

      {:ok, %{rows: []}} ->
        do_create_subscription(
          repo,
          connection_string,
          publication_name,
          subscription_name,
          copy_data,
          enabled
        )

      {:error, reason} = error ->
        log(
          "failed to check existing subscription name=#{subscription_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end

  @doc """
  Enables a subscription.

  Note: Before calling this, you should call
  `LogicalReplicator.ensure_slot_on_source/2` on the source repo
  to ensure the replication slot exists.

  ## Example

      # First ensure slot exists on source
      LogicalReplicator.ensure_slot_on_source(Chat.Repo, "main_from_internal")
      # Then enable subscription on target
      enable_subscription(MainRepo, "main_from_internal")
  """
  @spec enable_subscription(repo(), subscription_name()) :: :ok | {:error, term()}
  def enable_subscription(repo, subscription_name) do
    sql = "ALTER SUBSCRIPTION #{subscription_name} ENABLE"

    case repo.query(sql) do
      {:ok, _} ->
        log("enabled subscription name=#{subscription_name}", :info)
        :ok

      {:error, reason} = error ->
        log(
          "failed to enable subscription name=#{subscription_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end

  @doc """
  Disables a subscription.

  ## Example

      disable_subscription(Chat.MainRepo, "main_from_internal")
  """
  @spec disable_subscription(repo(), subscription_name()) :: :ok | {:error, term()}
  def disable_subscription(repo, subscription_name) do
    sql = "ALTER SUBSCRIPTION #{subscription_name} DISABLE"

    case repo.query(sql) do
      {:ok, _} ->
        log("disabled subscription name=#{subscription_name}", :info)
        :ok

      {:error, reason} = error ->
        log(
          "failed to disable subscription name=#{subscription_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end

  @spec disable_subscription_if_exists(repo(), subscription_name()) :: :ok | {:error, term()}
  def disable_subscription_if_exists(repo, subscription_name) do
    check_sql = "SELECT 1 FROM pg_subscription WHERE subname = '#{subscription_name}' LIMIT 1"

    case repo.query(check_sql) do
      {:ok, %{rows: []}} ->
        :ok

      {:ok, %{rows: [_ | _]}} ->
        disable_subscription(repo, subscription_name)

      {:error, reason} = error ->
        log(
          "failed to check subscription before disable name=#{subscription_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end

  @doc """
  Drops a subscription if it exists.

  This is useful for cleaning up stale subscriptions that point to old
  connection strings (e.g., after a USB drive is swapped).

  ## Example

      drop_subscription_if_exists(Chat.Repo, "internal_from_main")
  """
  @spec drop_subscription_if_exists(repo(), subscription_name()) :: :ok | {:error, term()}
  def drop_subscription_if_exists(repo, subscription_name) do
    check_sql = "SELECT 1 FROM pg_subscription WHERE subname = '#{subscription_name}' LIMIT 1"

    case repo.query(check_sql) do
      {:ok, %{rows: []}} ->
        :ok

      {:ok, %{rows: [_ | _]}} ->
        do_drop_subscription(repo, subscription_name)

      {:error, reason} = error ->
        log(
          "failed to check subscription name=#{subscription_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end

  defp do_create_subscription(
         repo,
         connection_string,
         publication_name,
         subscription_name,
         copy_data,
         enabled
       ) do
    create_sql = """
    CREATE SUBSCRIPTION #{subscription_name}
    CONNECTION '#{connection_string}'
    PUBLICATION #{publication_name}
    WITH (copy_data = #{copy_data}, enabled = #{enabled});
    """

    case repo.query(create_sql) do
      {:ok, _} ->
        log(
          "created subscription name=#{subscription_name} publication=#{publication_name} copy_data=#{copy_data} enabled=#{enabled}",
          :info
        )

        :ok

      {:error, %{postgres: %{message: msg}} = reason} = error ->
        if String.contains?(msg || "", "already exists") do
          create_without_slot(
            repo,
            connection_string,
            publication_name,
            subscription_name,
            copy_data,
            enabled
          )
        else
          log(
            "failed to create subscription name=#{subscription_name} reason=#{inspect(reason)}",
            :error
          )

          error
        end

      {:error, reason} = error ->
        log(
          "failed to create subscription name=#{subscription_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end

  defp create_without_slot(
         repo,
         connection_string,
         publication_name,
         subscription_name,
         copy_data,
         enabled
       ) do
    create_sql = """
    CREATE SUBSCRIPTION #{subscription_name}
    CONNECTION '#{connection_string}'
    PUBLICATION #{publication_name}
    WITH (copy_data = #{copy_data}, enabled = false, create_slot = false);
    """

    set_slot_sql =
      "ALTER SUBSCRIPTION #{subscription_name} SET (slot_name = '#{subscription_name}')"

    with {:ok, _} <- repo.query(create_sql),
         {:ok, _} <- repo.query(set_slot_sql) do
      if enabled, do: enable_subscription(repo, subscription_name)
      log("created subscription name=#{subscription_name} (reused existing slot)", :info)
      :ok
    else
      {:error, reason} = error ->
        log(
          "failed to create subscription without slot name=#{subscription_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end

  defp do_drop_subscription(repo, subscription_name) do
    _ = disable_subscription(repo, subscription_name)
    _ = repo.query("ALTER SUBSCRIPTION #{subscription_name} SET (slot_name = NONE)")

    case repo.query("DROP SUBSCRIPTION #{subscription_name}") do
      {:ok, _} ->
        log("dropped subscription name=#{subscription_name}", :info)
        :ok

      {:error, reason} = error ->
        log(
          "failed to drop subscription name=#{subscription_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end
end
