defmodule Chat.NetworkSynchronization.Electric.DeferredStore do
  @moduledoc """
  ETS-backed store for shape records deferred because their parents
  haven't arrived yet. Shared across all ShapeConsumers.
  """

  use GenServer
  use Toolbox.OriginLog

  import Ecto.Query

  alias Chat.Data.Shapes
  alias Chat.NetworkSynchronization.Electric.DeferredRecord
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Electric.Client.Message

  @table :buckitup_deferred_records
  @ttl_ms :timer.hours(2)
  @sweep_interval_ms :timer.minutes(5)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  @spec defer(atom(), Keyword.t(), :insert | :update, [{atom(), term()}], String.t()) :: :ok
  def defer(shape, key, operation, missing_parents, peer_url) do
    record = DeferredRecord.new(shape, key, operation, missing_parents, peer_url)

    Enum.each(missing_parents, fn {parent_shape, parent_key} ->
      :ets.insert(@table, {{parent_shape, parent_key}, record})
    end)
  end

  @spec check_children(atom(), term()) :: [DeferredRecord.t()]
  def check_children(parent_shape, parent_key) do
    @table
    |> :ets.take({parent_shape, parent_key})
    |> Enum.map(&elem(&1, 1))
  end

  @spec trigger_redeliver([DeferredRecord.t()]) :: :ok
  def trigger_redeliver(records) do
    GenServer.cast(__MODULE__, {:redeliver, records})
  end

  @spec purge_peer(String.t()) :: :ok
  def purge_peer(peer_url) do
    match_spec = [{{:_, %{peer_url: peer_url}}, [], [true]}]
    :ets.select_delete(@table, match_spec)
    :ok
  end

  @spec purge_shape(String.t(), atom()) :: :ok
  def purge_shape(peer_url, shape) do
    match_spec = [{{:_, %{peer_url: peer_url, shape: shape}}, [], [true]}]
    :ets.select_delete(@table, match_spec)
    :ok
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    table = table_name(Keyword.get(opts, :name, __MODULE__))
    ensure_table(table)
    schedule_sweep()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:redeliver, records}, state) do
    Enum.each(records, &spawn_refetch/1)
    {:noreply, state}
  end

  @impl true
  def handle_info(:ttl_sweep, %{table: table} = state) do
    cutoff = System.monotonic_time(:millisecond) - @ttl_ms
    match_spec = [{{:_, %{deferred_at: :"$1"}}, [{:<, :"$1", cutoff}], [true]}]
    :ets.select_delete(table, match_spec)
    schedule_sweep()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private

  defp table_name(__MODULE__), do: @table
  defp table_name(name), do: :"#{name}_deferred_records"

  defp ensure_table(table) do
    case :ets.info(table) do
      :undefined -> :ets.new(table, [:bag, :public, :named_table, write_concurrency: :auto])
      _ -> table
    end
  end

  defp schedule_sweep do
    Process.send_after(self(), :ttl_sweep, @sweep_interval_ms)
  end

  defp spawn_refetch(%DeferredRecord{} = record) do
    Task.Supervisor.start_child(Chat.TaskSupervisor, fn ->
      refetch(record)
    end)
  end

  defp refetch(%DeferredRecord{shape: shape, key: pk, peer_url: peer_url}) do
    peer_url
    |> shapes_client()
    |> Electric.Client.stream(build_refetch_query(shape, pk), live: false, replica: :full)
    |> Stream.each(&replay_change(shape, &1, peer_url))
    |> Stream.run()
  catch
    kind, reason ->
      log("Deferred redeliver failed for #{shape}: #{inspect({kind, reason})}", :warning)
  end

  defp shapes_client(peer_url) do
    Electric.Client.new!(
      endpoint: "#{peer_url}/electric/v1/shapes",
      fetch:
        {Electric.Client.Fetch.HTTP,
         request: [connect_options: [transport_opts: [{:keepalive, true}]]]}
    )
  end

  defp replay_change(
         shape,
         %Message.ChangeMessage{headers: %{operation: op}, value: value},
         peer_url
       ) do
    ShapeWriter.write(shape, op, value, peer_url: peer_url)
  end

  defp replay_change(_shape, _msg, _peer_url), do: :ok

  defp build_refetch_query(shape, primary_key_kw) do
    schema_mod = Shapes.by_name(shape).schema_module()

    Enum.reduce(primary_key_kw, from(r in schema_mod), fn {field, value}, q ->
      from(r in q, where: field(r, ^field) == ^value)
    end)
  end
end
