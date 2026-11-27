defmodule Chat.Db.Boot.RepoReadyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Rewire

  alias Chat.Db.Boot.RepoReady
  alias Ecto.Adapters.SQL.Sandbox

  defmodule FakeRepo do
    @moduledoc false
    def child_spec(_), do: %{id: __MODULE__, start: {Agent, :start_link, [fn -> :repo end]}}
  end

  defmodule MigratorStub do
    @moduledoc false
    def run(FakeRepo, _path, :up, all: true), do: [20_260_101_000_000, 20_260_102_000_000]
  end

  rewire(RepoReady, [{Chat.Repo, FakeRepo}, {Ecto.Migrator, MigratorStub}, as: StubbedRepoReady])

  setup do
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: __MODULE__.Repos})
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: __MODULE__.Next})
    :ok
  end

  describe "stage" do
    test "starts the repo under the given supervisor and starts the next stage" do
      next = [under: __MODULE__.Next, run: [{Agent, fn -> :next_stage end}]]

      start_supervised!({StubbedRepoReady, supervisor: __MODULE__.Repos, next: next})

      assert_eventually(fn -> DynamicSupervisor.count_children(__MODULE__.Next).active == 1 end)
      assert %{active: 1} = DynamicSupervisor.count_children(__MODULE__.Repos)
    end

    test "without a next stage it only starts the repo" do
      start_supervised!({StubbedRepoReady, supervisor: __MODULE__.Repos})

      assert_eventually(fn -> DynamicSupervisor.count_children(__MODULE__.Repos).active == 1 end)
      assert %{active: 0} = DynamicSupervisor.count_children(__MODULE__.Next)
    end
  end

  describe "run_migrations/1" do
    test "returns the applied migrations" do
      assert [_, _] = StubbedRepoReady.run_migrations(FakeRepo)
    end

    test "returns [] when the repo is up to date" do
      :ok = Sandbox.checkout(Chat.Repo)

      log = capture_log(fn -> assert [] = RepoReady.run_migrations(Chat.Repo) end)

      refute log =~ "failed"
    end

    test "logs and returns [] when migrating fails" do
      log = capture_log(fn -> assert [] = RepoReady.run_migrations(FakeRepo) end)

      assert log =~ "Migration on #{FakeRepo} failed"
    end
  end

  defp assert_eventually(check, attempts \\ 100) do
    cond do
      check.() -> :ok
      attempts == 0 -> flunk("condition not met in time")
      true -> Process.sleep(10) && assert_eventually(check, attempts - 1)
    end
  end
end
