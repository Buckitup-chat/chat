defmodule Chat.Admin.AdminDbLoggerTest do
  use ExUnit.Case, async: true

  require Logger
  alias Chat.AdminDb
  alias Chat.AdminDb.AdminLogger

  test "prev generation removal should work" do
    starting_generation = populate_3_more_generation()
    current_generation = AdminLogger.get_current_generation()

    assert current_generation > starting_generation
    assert 0 < count_generation_rows(starting_generation)

    AdminLogger.remove_old_generations(current_generation)
    Process.sleep(200)
    assert 0 = count_generation_rows(starting_generation)

    assert 0 < count_generation_rows(current_generation)

    assert 0 < Enum.count(AdminLogger.get_log())
    assert 0 < Enum.count(AdminLogger.get_log(:prev))
    assert 0 < Enum.count(AdminLogger.get_log(:prev_prev))
  end

  defp populate_3_more_generation do
    starting_generation = AdminLogger.get_current_generation()

    log_something()

    Logger.remove_backend(AdminLogger)
    {:ok, _pid} = Logger.add_backend(AdminLogger)
    log_something()

    Logger.remove_backend(AdminLogger)
    {:ok, _pid} = Logger.add_backend(AdminLogger)
    log_something()

    Logger.remove_backend(AdminLogger)
    {:ok, _pid} = Logger.add_backend(AdminLogger)
    log_something()

    starting_generation
  end

  defp log_something do
    Logger.debug("1")
    Logger.info("2")
    Logger.warning("3")
    Logger.error("4")

    Process.sleep(100)
  end

  defp count_generation_rows(generation) do
    AdminDb.db()
    |> CubDB.select(min_key: {:log, generation, 0}, max_key: {:log, generation, nil})
    |> Enum.count()
  end
end
