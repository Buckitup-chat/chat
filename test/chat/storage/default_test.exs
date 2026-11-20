defmodule Chat.Storage.DefaultTest do
  use ExUnit.Case, async: false

  import Rewire

  alias Chat.Db.Common
  alias Chat.Db.Switching
  alias Chat.Storage.Default
  alias Chat.Storage.Unit

  rewire(Default, [
    {Chat.Storage.Default.Electric, ChatSupport.Mocks.Storage.DefaultElectricMock},
    {Chat.Sync.DbBrokers, ChatSupport.Mocks.Storage.DbBrokersMock}
  ])

  @key {Chat.Storage.Default, :unit}

  setup do
    Application.put_env(:chat, :default_electric_mock_pid, self())
    Phoenix.PubSub.subscribe(Chat.PubSub, "storage")

    on_exit(fn ->
      Application.delete_env(:chat, :default_electric_mock_pid)
      :persistent_term.erase(@key)
      Switching.set_default(Chat.Db.InternalDb)
    end)

    %{main: Unit.usb("sdb", :main)}
  end

  test "unit/0 is internal before any switch" do
    :persistent_term.erase(@key)
    assert Default.unit() == Unit.internal()
    assert Chat.Db.repo() == Chat.Repo
  end

  test "switch_to/1 runs the spec steps in order", %{main: main} do
    internal = Unit.internal()

    assert :ok = Default.switch_to(main)

    # Electric stops while the old unit is still Default, and is released there
    assert_received {:electric, :stop, :internal, Chat.Repo}
    assert_received {:electric, {:release, :internal}, :internal, Chat.Repo}
    # Electric starts after CubDB, repo and upload writer point at the new unit
    assert_received {:electric, {:start, "sdb"}, "sdb", Platform.Dev.Sdb.Repo}
    assert_received {:default_switched, ^main}

    assert Default.unit() == main
    assert Common.get_chat_db_env(:data_pid) == Chat.Db.MainDb
    assert Common.get_chat_db_env(:data_queue) == Common.names(Chat.Db.MainDb, :queue)

    assert :ok = Default.switch_to(internal)
    assert_received {:electric, {:release, "sdb"}, "sdb", _}
    assert_received {:electric, {:start, :internal}, :internal, Chat.Repo}
    assert Common.get_chat_db_env(:data_pid) == Chat.Db.InternalDb
  end

  test "switching to the current unit keeps its Electric state" do
    assert :ok = Default.switch_to(Unit.internal())

    assert_received {:electric, :stop, _, _}
    refute_received {:electric, {:release, _}, _, _}
    assert_received {:electric, {:start, :internal}, _, _}
  end

  test "repo and upload writer never point at different units during switches", %{main: main} do
    Application.delete_env(:chat, :default_electric_mock_pid)
    units = [Unit.internal(), main]

    switcher =
      Task.async(fn -> for _ <- 1..50, unit <- units, do: Default.switch_to(unit) end)

    # An upload reads the Default once and derives the writer and the repo from it
    snapshots =
      Stream.repeatedly(fn ->
        unit = Default.unit()
        {unit.id, Unit.repo(unit), Unit.path(unit, :pq_files)}
      end)
      |> Enum.take(5_000)

    Task.await(switcher, 30_000)

    expected = Enum.map(units, &{&1.id, Unit.repo(&1), Unit.path(&1, :pq_files)})
    assert snapshots |> Enum.uniq() |> Enum.all?(&(&1 in expected))
  end
end
