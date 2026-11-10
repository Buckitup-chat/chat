defmodule Chat.Test.PgPairCase do
  @moduledoc """
  Case template for tests that need two PostgreSQL databases (`Chat.Test.PgPairHelper`).

      use Chat.Test.PgPairCase, mode: :sandbox                  # diff-copy (BatchSync)
      use Chat.Test.PgPairCase, mode: :committed, async: false  # logical replication, Link

  - `:sandbox` (default) — both repos checked out in a rolled-back transaction.
  - `:committed` — no transaction, so replication sees the rows. Must be `async: false`;
    `on_exit` drops subscriptions, publications, slots and truncates the tables.

  Tests are tagged `:pg_pair` and get `unit_a` / `unit_b` fixtures in the context.
  """

  use ExUnit.CaseTemplate

  alias Chat.Test.PgPairHelper
  alias Chat.Test.{UnitARepo, UnitBRepo}

  using opts do
    mode = Keyword.get(opts, :mode, :sandbox)

    case {mode, Keyword.get(opts, :async, false)} do
      {mode, _} when mode not in [:sandbox, :committed] ->
        raise ArgumentError,
              "PgPairCase mode must be :sandbox or :committed, got: #{inspect(mode)}"

      {:committed, true} ->
        raise ArgumentError, "PgPairCase mode: :committed requires async: false"

      _ ->
        :ok
    end

    quote do
      import Chat.Test.PgPairHelper
      import Ecto.Query

      alias Chat.Test.{UnitARepo, UnitBRepo}

      @moduletag :pg_pair
      @moduletag pg_pair_mode: unquote(mode)
    end
  end

  setup_all do
    PgPairHelper.ensure_ready()
  end

  setup tags do
    PgPairHelper.checkout(tags.pg_pair_mode, not tags.async)

    case tags.pg_pair_mode do
      :committed -> on_exit(&PgPairHelper.reset/0)
      :sandbox -> :ok
    end

    root = Path.join(System.tmp_dir!(), "pg_pair_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      unit_a: PgPairHelper.unit_fixture(UnitARepo, Path.join(root, "a")),
      unit_b: PgPairHelper.unit_fixture(UnitBRepo, Path.join(root, "b"))
    }
  end
end
