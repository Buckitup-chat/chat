defmodule Chat.Storage.Default.ElectricTest do
  use Chat.Test.PgPairCase, mode: :committed, async: false

  import ExUnit.CaptureLog
  import Support.Rewire

  alias Chat.Storage.Default.Electric
  alias Chat.Storage.Unit
  alias ChatSupport.Mocks.PhoenixSync.ApplicationMock

  defmodule InfoChild do
    @moduledoc false
    def child_spec(_), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}

    def start_link do
      {:ok, pid} = Agent.start_link(fn -> :info end)
      {:ok, pid, :info}
    end
  end

  defmodule TupleChild do
    @moduledoc false
    def child_spec(arg), do: %{id: __MODULE__, start: {Agent, :start_link, [fn -> arg end]}}
  end

  defmodule AtomChild do
    @moduledoc false
    use Agent

    def start_link(_), do: Agent.start_link(fn -> :atom end)
  end

  defmodule MapChild do
    @moduledoc false
    def start_link, do: Agent.start_link(fn -> :map end)
    def fail, do: {:error, :boom}
  end

  defmodule StubbornStack do
    @moduledoc false
    use GenServer

    def init(:ok), do: {:ok, nil}
    def terminate(_reason, _state), do: raise("refuses to stop")
  end

  rewire(Electric, [{Phoenix.Sync.Application, ApplicationMock}])

  @sync Phoenix.Sync.Supervisor
  @stack Elixir.Electric.StackSupervisor
  @map_child %{id: MapChild, start: {MapChild, :start_link, []}}
  @children [@map_child, InfoChild, {TupleChild, :tuple}, AtomChild]
  @child_ids [AtomChild, InfoChild, MapChild, TupleChild]

  @slots "SELECT slot_name FROM pg_replication_slots WHERE slot_name = 'electric_slot_default'"
  @pubs "SELECT pubname FROM pg_publication WHERE pubname = 'electric_publication_default'"

  setup do
    config = Application.get_all_env(:phoenix_sync)
    Application.put_env(:phoenix_sync, :mode, :embedded)
    Application.put_env(:chat, :phoenix_sync_children_mock, {:ok, []})
    :ok = Electric.release_pg(UnitARepo)

    on_exit(fn ->
      Application.get_all_env(:phoenix_sync)
      |> Enum.each(fn {key, _} -> Application.delete_env(:phoenix_sync, key) end)

      Enum.each(config, fn {key, value} -> Application.put_env(:phoenix_sync, key, value) end)
      Application.delete_env(:chat, :phoenix_sync_children_mock)

      Enum.each([@stack | @child_ids], fn id ->
        _ = Supervisor.terminate_child(@sync, id)
        _ = Supervisor.delete_child(@sync, id)
      end)
    end)
  end

  test "slot and publication names" do
    assert Electric.slot() == "electric_slot_default"
    assert Electric.publication() == "electric_publication_default"
  end

  test "ensure_slot/1 creates electric_slot_default once" do
    assert :ok = Electric.ensure_slot(UnitARepo)
    assert :ok = Electric.ensure_slot(UnitARepo)
    assert %{rows: [["electric_slot_default"]]} = UnitARepo.query!(@slots)
  end

  test "release_pg/1 leaves no Electric slot or publication on the old unit" do
    :ok = Electric.ensure_slot(UnitARepo)
    UnitARepo.query!("CREATE PUBLICATION electric_publication_default")

    assert :ok = Electric.release_pg(UnitARepo)

    assert %{rows: []} = UnitARepo.query!(@slots)
    assert %{rows: []} = UnitARepo.query!(@pubs)
    # idempotent when nothing is left
    assert :ok = Electric.release_pg(UnitARepo)
  end

  test "ensure_slot/1 is a no-op outside embedded mode" do
    Application.put_env(:phoenix_sync, :mode, :sandbox)

    assert :ok = Electric.ensure_slot(UnitARepo)
    assert %{rows: []} = UnitARepo.query!(@slots)
  end

  test "start/1 puts repo, connection opts and the unit's electric dir into phoenix_sync env" do
    # no slot on Chat.Repo: it is the sandboxed test repo
    Application.put_env(:phoenix_sync, :mode, :sandbox)
    unit = Unit.internal()

    assert :ok = Electric.start(unit)

    assert Application.get_env(:phoenix_sync, :repo) == Chat.Repo

    assert Application.get_env(:phoenix_sync, :storage_dir) ==
             Unit.path(unit, :electric)

    assert Application.get_env(:phoenix_sync, :connection_opts)[:hostname]
  end

  test "start/1 propagates a children error" do
    Application.put_env(:phoenix_sync, :mode, :sandbox)
    Application.put_env(:chat, :phoenix_sync_children_mock, {:error, :config_error})

    assert {:error, :config_error} = Electric.start(Unit.internal())
  end

  test "stop/0 is safe when the stack is not running" do
    assert :ok = Electric.stop()
  end

  describe "release/1" do
    test "drops the slot, the publication and the electric cache of the unit", %{unit_a: unit} do
      :ok = Electric.ensure_slot(UnitARepo)
      UnitARepo.query!("CREATE PUBLICATION electric_publication_default")
      cache = Unit.path(unit, :electric)
      File.mkdir_p!(cache)

      assert :ok = Electric.release(unit)

      assert %{rows: []} = UnitARepo.query!(@slots)
      assert %{rows: []} = UnitARepo.query!(@pubs)
      refute File.exists?(cache)
    end

    test "keeps the cache outside embedded mode", %{unit_a: unit} do
      Application.put_env(:phoenix_sync, :mode, :sandbox)
      cache = Unit.path(unit, :electric)
      File.mkdir_p!(cache)

      assert :ok = Electric.release(unit)

      assert File.exists?(cache)
    end
  end

  describe "start/1" do
    test "ensures the slot on the unit's repo in embedded mode", %{unit_a: unit} do
      assert :ok = Electric.start(unit)

      assert %{rows: [["electric_slot_default"]]} = UnitARepo.query!(@slots)
      assert Application.get_env(:phoenix_sync, :repo) == UnitARepo
    end

    test "starts every child under Phoenix.Sync.Supervisor, also when already started" do
      use_sandbox_children(@children)

      assert :ok = Electric.start(Unit.internal())
      assert :ok = Electric.start(Unit.internal())

      assert running_ids() == @child_ids
    end

    test "replaces child specs left over from a stopped stack" do
      use_sandbox_children(@children)
      :ok = Electric.start(Unit.internal())
      Enum.each(@child_ids, &Supervisor.terminate_child(@sync, &1))

      assert :ok = Electric.start(Unit.internal())

      assert running_ids() == @child_ids
    end

    test "halts on the first child that fails to start" do
      use_sandbox_children([%{id: MapChild, start: {MapChild, :fail, []}}, AtomChild])

      capture_log(fn -> assert {:error, {:boom, _}} = Electric.start(Unit.internal()) end)

      assert running_ids() == []
    end
  end

  defp use_sandbox_children(children) do
    Application.put_env(:phoenix_sync, :mode, :sandbox)
    Application.put_env(:chat, :phoenix_sync_children_mock, {:ok, children})
  end

  describe "stop/0" do
    test "terminates and removes the stack under Phoenix.Sync.Supervisor" do
      stack = %{id: @stack, start: {Agent, :start_link, [fn -> :stack end, [name: @stack]]}}
      {:ok, pid} = Supervisor.start_child(@sync, stack)

      assert :ok = Electric.stop()

      refute Process.alive?(pid)
      refute Enum.any?(Supervisor.which_children(@sync), &match?({@stack, _, _, _}, &1))
    end

    test "stops a stack running outside Phoenix.Sync.Supervisor" do
      {:ok, pid} = Agent.start(fn -> :stack end, name: @stack)

      assert :ok = Electric.stop()

      refute Process.alive?(pid)
    end

    test "logs and returns :ok when the stack fails to stop" do
      {:ok, _pid} = GenServer.start(StubbornStack, :ok, name: @stack)

      log = capture_log(fn -> assert :ok = Electric.stop() end)

      assert log =~ "stopping Electric stack failed"
      refute Process.whereis(@stack)
    end
  end

  defp running_ids do
    @sync
    |> Supervisor.which_children()
    |> Enum.flat_map(fn
      {id, pid, _, _} when id in @child_ids and is_pid(pid) -> [id]
      _ -> []
    end)
    |> Enum.sort()
  end
end
