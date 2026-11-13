defmodule Chat.Storage.Default.ElectricTest do
  use Chat.Test.PgPairCase, mode: :committed, async: false

  import Rewire

  alias Chat.Storage.Default.Electric
  alias Chat.Storage.Unit
  alias ChatSupport.Mocks.PhoenixSync.ApplicationMock

  rewire(Electric, [{Phoenix.Sync.Application, ApplicationMock}])

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
    end)
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
end
