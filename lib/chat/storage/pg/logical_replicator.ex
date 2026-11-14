defmodule Chat.Storage.Pg.LogicalReplicator do
  @moduledoc """
  Manages PostgreSQL logical replication publications, slots, following, and lag checking.

  Subscription management is in `Chat.Storage.Pg.LogicalReplicator.Subscription`.

  Uses PostgreSQL's native logical replication (available since PG 10).
  """

  use Toolbox.OriginLog

  alias Chat.Storage.Pg
  alias Chat.Storage.Pg.LogicalReplicator.Subscription

  @slot_drop_attempts 20
  @slot_drop_retry_ms 100

  @type repo :: module()
  @type table_name :: String.t()
  @type publication_name :: String.t()

  # --- Delegated Subscription functions ---

  defdelegate create_subscription(repo, conn_string, pub_name, sub_name, opts \\ []),
    to: Subscription

  defdelegate enable_subscription(repo, subscription_name), to: Subscription
  defdelegate disable_subscription(repo, subscription_name), to: Subscription
  defdelegate disable_subscription_if_exists(repo, subscription_name), to: Subscription
  defdelegate drop_subscription_if_exists(repo, subscription_name), to: Subscription

  # --- Publications ---

  @doc """
  Creates a publication on the given repo for the specified tables.

  If the publication already exists, this is a no-op.

  ## Example

      tables = Chat.Data.Shapes.sync_tables()
      create_publication(Chat.Repo, tables, "internal_to_main")
  """
  @spec create_publication(repo(), [table_name()], publication_name()) ::
          :ok | {:error, term()}
  def create_publication(repo, tables, publication_name) do
    tables_list = Enum.join(tables, ", ")

    sql = """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = '#{publication_name}') THEN
        CREATE PUBLICATION #{publication_name} FOR TABLE #{tables_list};
      ELSE
        ALTER PUBLICATION #{publication_name} SET TABLE #{tables_list};
      END IF;
    END $$;
    """

    case repo.query(sql) do
      {:ok, _} ->
        log("ensured publication name=#{publication_name} tables=#{inspect(tables)}", :info)
        :ok

      {:error, reason} = error ->
        log(
          "failed to create publication name=#{publication_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end

  # --- Follow (publication + slot on source, subscription on target) ---

  @doc """
  Makes `target_repo` live-follow `tables` of `source_repo`.

  Starts from a fresh slot every time (any previous subscription and slot are
  dropped first), so a stale slot never replays rows already copied. The slot is
  created before the subscription: a subscription creating its own slot hangs
  when source and target share a cluster. Existing data is not copied.
  """
  @spec follow(repo(), repo(), [table_name()], publication_name(), String.t()) ::
          :ok | {:error, term()}
  def follow(source_repo, target_repo, tables, publication_name, slot_name) do
    with :ok <- drop_subscription_if_exists(target_repo, slot_name),
         :ok <- release_slot(source_repo, slot_name),
         :ok <- create_publication(source_repo, tables, publication_name),
         :ok <- ensure_slot_on_source(source_repo, slot_name),
         :ok <-
           create_subscription(
             target_repo,
             Pg.build_connection_string(source_repo),
             publication_name,
             slot_name,
             copy_data: false,
             enabled: false
           ) do
      enable_subscription(target_repo, slot_name)
    end
  end

  @doc """
  Terminates the walsender still holding the slot (e.g. a subscriber whose
  database is gone), then drops the slot. Retries while the slot is still busy.
  """
  @spec release_slot(repo(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def release_slot(source_repo, slot_name, attempts \\ @slot_drop_attempts) do
    _ =
      source_repo.query(
        """
        SELECT pg_terminate_backend(active_pid) FROM pg_replication_slots
        WHERE slot_name = $1 AND active_pid IS NOT NULL
        """,
        [slot_name]
      )

    case drop_slot_if_exists(source_repo, slot_name) do
      {:error, _reason} when attempts > 1 ->
        Process.sleep(@slot_drop_retry_ms)
        release_slot(source_repo, slot_name, attempts - 1)

      result ->
        result
    end
  end

  # --- Replication slots ---

  @doc """
  Drops a replication slot if it exists on the source repo.

  This is useful for cleaning up stale slots from previous sessions that
  weren't properly cleaned up (e.g., after a crash).

  ## Example

      drop_slot_if_exists(Chat.Repo, "main_from_internal")
  """
  @spec drop_slot_if_exists(repo(), String.t()) :: :ok | {:error, term()}
  def drop_slot_if_exists(source_repo, slot_name) do
    check_sql = "SELECT 1 FROM pg_replication_slots WHERE slot_name = '#{slot_name}'"
    drop_sql = "SELECT pg_drop_replication_slot('#{slot_name}')"

    with {:ok, %{rows: [_ | _]}} <- source_repo.query(check_sql),
         {:ok, _} <- source_repo.query(drop_sql) do
      log("dropped stale slot=#{slot_name}", :info)
      :ok
    else
      {:ok, %{rows: []}} ->
        :ok

      {:error, reason} = error ->
        log("failed to drop slot=#{slot_name} reason=#{inspect(reason)}", :warning)
        error
    end
  end

  @doc """
  Ensures a replication slot exists on the source repo.

  This should be called BEFORE enabling a subscription to ensure the slot
  exists on the source database. If the slot already exists, this is a no-op.

  ## Example

      ensure_slot_on_source(Chat.Repo, "main_from_internal")
  """
  @spec ensure_slot_on_source(repo(), String.t()) :: :ok | {:error, term()}
  def ensure_slot_on_source(source_repo, slot_name) do
    check_sql = """
    SELECT 1 FROM pg_replication_slots WHERE slot_name = '#{slot_name}'
    """

    case source_repo.query(check_sql) do
      {:ok, %{rows: [_ | _]}} ->
        log("slot=#{slot_name} already exists on source", :debug)
        :ok

      {:ok, %{rows: []}} ->
        create_sql = """
        SELECT pg_create_logical_replication_slot('#{slot_name}', 'pgoutput')
        """

        case source_repo.query(create_sql) do
          {:ok, _} ->
            log("created slot=#{slot_name} on source", :info)
            :ok

          {:error, reason} = error ->
            log("failed to create slot=#{slot_name} on source reason=#{inspect(reason)}", :error)
            error
        end

      {:error, reason} = error ->
        log("failed to check slot=#{slot_name} on source reason=#{inspect(reason)}", :error)
        error
    end
  end

  # --- Replication lag ---

  @doc """
  Checks replication lag for a subscription via pg_stat_subscription.

  Returns the lag in bytes, or {:error, reason} if the subscription is not found
  or an error occurs.

  ## Example

      check_replication_lag(Chat.MainRepo, "main_from_internal")
      # => {:ok, 0} (no lag)
      # => {:ok, 1024} (1KB lag)
  """
  @spec check_replication_lag(repo(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def check_replication_lag(repo, subscription_name) do
    sql = """
    SELECT
      -- received_lsn can run ahead of latest_end_lsn, which made the diff negative
      GREATEST(COALESCE(pg_wal_lsn_diff(latest_end_lsn, received_lsn), 0), 0) AS lag_bytes
    FROM pg_stat_subscription
    WHERE subname = '#{subscription_name}'
    """

    case repo.query(sql) do
      {:ok, %{rows: [[lag_bytes]]}} when is_number(lag_bytes) ->
        {:ok, trunc(lag_bytes)}

      {:ok, %{rows: [[%Decimal{} = lag_bytes]]}} ->
        {:ok, Decimal.to_integer(lag_bytes)}

      {:ok, %{rows: []}} ->
        {:error, :subscription_not_found}

      {:error, reason} = error ->
        log(
          "failed to check lag subscription=#{subscription_name} reason=#{inspect(reason)}",
          :error
        )

        error
    end
  end
end
