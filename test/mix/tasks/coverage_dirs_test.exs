defmodule Mix.Tasks.Coverage.DirsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Coverage.Dirs

  @files [
    %{"name" => "lib/chat/a.ex", "coverage" => [nil, 1, 1, 0]},
    %{"name" => "lib/chat/b.ex", "coverage" => [3, nil, 0, 1]},
    %{"name" => "lib/chat_web/c.ex", "coverage" => [1, 0, 0, 0]},
    %{"name" => "lib/chat.ex", "coverage" => [0, 0]}
  ]

  describe "check/2" do
    test "aggregates relevant lines by prefix, keeping lib/chat/ apart from lib/chat_web/" do
      assert [chat, chat_web] = Dirs.check(@files, %{"lib/chat_web/" => 20, "lib/chat/" => 70})

      assert %{dir: "lib/chat/", min: 70, ok?: false} = chat
      assert_in_delta chat.percent, 66.67, 0.01
      assert %{dir: "lib/chat_web/", percent: 25.0, min: 20, ok?: true} = chat_web
    end

    test "a prefix that matches nothing counts as 0% and fails" do
      assert [%{dir: "lib/nowhere/", percent: +0.0, ok?: false}] =
               Dirs.check(@files, %{"lib/nowhere/" => 1})
    end
  end

  describe "run/1" do
    @tag :tmp_dir
    test "passes and prints every directory when all thresholds hold", %{tmp_dir: dir} do
      args = write_inputs(dir, %{"lib/chat/" => 60, "lib/chat_web/" => 25})

      output = capture_io(fn -> Dirs.run(args) end)

      assert output =~ "ok   lib/chat/ 66.7% (min 60%)"
      assert output =~ "ok   lib/chat_web/ 25.0% (min 25%)"
    end

    @tag :tmp_dir
    test "raises naming the directories below threshold", %{tmp_dir: dir} do
      args = write_inputs(dir, %{"lib/chat/" => 90, "lib/chat_web/" => 75})

      output =
        capture_io(fn ->
          assert_raise Mix.Error, "Coverage below threshold: lib/chat/, lib/chat_web/", fn ->
            Dirs.run(args)
          end
        end)

      assert output =~ "FAIL lib/chat/ 66.7% (min 90%)"
    end
  end

  # Helpers

  defp write_inputs(dir, thresholds) do
    report = Path.join(dir, "excoveralls.json")
    config = Path.join(dir, "coveralls.json")

    File.write!(report, Jason.encode!(%{"source_files" => @files}))
    File.write!(config, Jason.encode!(%{"dir_thresholds" => thresholds}))

    ["--report", report, "--config", config]
  end
end
