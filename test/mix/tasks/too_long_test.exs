defmodule Mix.Tasks.TooLongTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.TooLong

  describe "check/3" do
    test "files under the limit and baseline files within their count pass" do
      counts = %{"lib/a.ex" => 10, "lib/big.ex" => 400}

      assert [] = TooLong.check(counts, %{"lib/big.ex" => 400}, 300)
    end

    test "a new file over the limit fails" do
      assert [%{path: "lib/a.ex", status: :new, lines: 301, baseline: nil}] =
               TooLong.check(%{"lib/a.ex" => 301}, %{}, 300)
    end

    test "a baseline file that grew fails" do
      assert [%{path: "lib/big.ex", status: :grew, lines: 401, baseline: 400}] =
               TooLong.check(%{"lib/big.ex" => 401}, %{"lib/big.ex" => 400}, 300)
    end

    test "a baseline file that shrank, dropped under the limit or is gone is stale" do
      counts = %{"lib/a.ex" => 350, "lib/b.ex" => 200}
      baseline = %{"lib/a.ex" => 400, "lib/b.ex" => 310, "lib/gone.ex" => 500}

      assert [
               %{path: "lib/a.ex", status: :stale, lines: 350},
               %{path: "lib/b.ex", status: :stale, lines: 200},
               %{path: "lib/gone.ex", status: :stale, lines: 0}
             ] = TooLong.check(counts, baseline, 300)
    end
  end

  describe "shrink/3" do
    test "lowers stale counts and drops entries under the limit, leaving the rest" do
      baseline = %{"lib/a.ex" => 400, "lib/b.ex" => 310, "lib/c.ex" => 500}

      problems =
        TooLong.check(%{"lib/a.ex" => 350, "lib/b.ex" => 200, "lib/c.ex" => 500}, baseline, 300)

      assert %{"lib/a.ex" => 350, "lib/c.ex" => 500} == TooLong.shrink(baseline, problems, 300)
    end
  end

  describe "run/1" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      cwd = File.cwd!()
      File.cd!(dir)
      on_exit(fn -> File.cd!(cwd) end)
      File.mkdir_p!("lib")
      :ok
    end

    test "passes when nothing is over the limit" do
      write_lines("lib/a.ex", 3)

      assert capture_io(fn -> TooLong.run(["--limit", "5"]) end) =~ "No new or grown files"
    end

    test "fails and names a new file over the limit" do
      write_lines("lib/a.ex", 6)

      output =
        capture_io(fn ->
          assert_raise Mix.Error, ~r/1 file\(s\) break the 5-line limit/, fn ->
            TooLong.run(["--limit", "5"])
          end
        end)

      assert output =~ "NEW   lib/a.ex 6 lines"
    end

    test "--update records a shrunk file but never admits a grown one" do
      write_lines("lib/shrunk.ex", 7)
      write_lines("lib/grown.ex", 9)
      File.write!(".too_long_baseline", "8 lib/grown.ex\n# comment\n10 lib/shrunk.ex\n")

      capture_io(fn ->
        assert_raise Mix.Error, fn -> TooLong.run(["--limit", "5", "--update"]) end
      end)

      assert File.read!(".too_long_baseline") == "8 lib/grown.ex\n7 lib/shrunk.ex\n"
    end
  end

  defp write_lines(file, n), do: File.write!(file, String.duplicate("x\n", n))
end
