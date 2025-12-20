defmodule Chat.Admin.AdminNoDbLoggerTest do
  use ExUnit.Case, async: false
  use Rewire

  require Logger
  alias Chat.AdminDb.AdminLogger

  defmodule AdminDbMock do
    def db, do: raise("AdminDB not started")
    def put(_key, _value), do: raise("AdminDB not started")
  end

  defmodule CubDbMock do
    def select(_db, _opts), do: raise("Database not available")
    def file_sync(_db), do: raise("Database not available")
  end

  rewire(AdminLogger, [{Chat.AdminDb, AdminDbMock}, {CubDB, CubDbMock}])

  setup do
    Logger.remove_backend(AdminLogger)

    Process.sleep(10)
    :ok
  end

  test "start logger without DB" do
    assert {:ok, _pid} = Logger.add_backend(AdminLogger)

    Logger.remove_backend(AdminLogger)
  end

  test "write into logger when DB is down" do
    {:ok, _pid} = Logger.add_backend(AdminLogger)

    Logger.debug("Test debug message")
    Logger.info("Test info message")
    Logger.warning("Test warning message")
    Logger.error("Test error message")

    Process.sleep(50)

    Logger.flush()
    Logger.remove_backend(AdminLogger)
  end

  test "logger handles flush gracefully when DB is down" do
    {:ok, _pid} = Logger.add_backend(AdminLogger)

    Logger.info("Test message before flush")
    Logger.flush()

    Logger.info("Test message after flush")
    Logger.remove_backend(AdminLogger)
  end

  test "adding logger twice" do
    {:ok, _pid} = Logger.add_backend(AdminLogger)
    {:ok, _pid} = Logger.add_backend(AdminLogger)

    Logger.remove_backend(AdminLogger)
  end
end
