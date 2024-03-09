defmodule ChatTest.IsolatedDataCase do
  @moduledoc "Test case that isolates data between tests"
  use ExUnit.CaseTemplate, async: false

  alias Chat.Db

  using options do
    quote do
      import ChatTest.IsolatedDataCase, only: [use_db: 2, db_name: 2]
      alias ChatTest.IsolatedDataCase

      setup_all context do
        default_db = Chat.Db.db()

        for db <- unquote(options) |> Keyword.fetch!(:dbs) do
          {db, IsolatedDataCase.start_db(context.module, db)}
        end
        |> Map.new()
        |> tap(fn isolated_dbs ->
          on_exit(fn ->
            IsolatedDataCase.use_db(context, default_db)
            IsolatedDataCase.clear_dbs(isolated_dbs)
          end)
        end)
        |> then(&Map.put(context, :isolated_dbs, &1))
      end
    end
  end

  def db_name(%{isolated_dbs: dbs}, db) do
    Map.get(dbs, db) || db
  end

  def db_name(_, db), do: db

  def use_db(context, db) do
    tap(context, fn context ->
      context
      |> db_name(db)
      |> switch_on
    end)
  end

  defp switch_on(db) do
    Db.Switching.set_default(db)
    Chat.Ordering.reset()
  end

  def start_db(test_name, db) do
    hash =
      [test_name, db]
      |> inspect()
      |> Enigma.short_hash()

    base_dir =
      [System.tmp_dir!(), hash]
      |> Path.join()
      |> tap(&File.rm_rf!(&1))

    :"Db_#{db}_#{hash}"
    |> tap(fn db_name ->
      %{
        id: make_ref(),
        start:
          {Supervisor, :start_link,
           [
             Chat.Db.supervise(db_name, [base_dir, "db"] |> Path.join()),
             [strategy: :rest_for_one]
           ]},
        type: :supervisor
      }
      |> start_supervised
    end)
    |> tap(fn db_name -> CubDB.set_auto_compact(db_name, false) end)
  end

  def clear_dbs(isolated_dbs) do
    isolated_dbs
    |> Enum.each(fn {_, db} ->
      if pid = Process.whereis(db) do
        pid
        |> CubDB.data_dir()
        |> Path.dirname()
        |> File.rm_rf!()
      end
    end)
  end
end
