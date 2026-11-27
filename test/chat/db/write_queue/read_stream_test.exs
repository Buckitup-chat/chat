defmodule Chat.Db.WriteQueue.ReadStreamTest do
  use ExUnit.Case, async: true

  import Chat.Db.WriteQueue.ReadStream
  import ExUnit.CaptureLog

  test "stream of a dead db finishes and notifies the awaiter" do
    stream =
      __MODULE__.MissingDb
      |> read_stream_new([:some_key])
      |> set_awaiter(self())

    log =
      capture_log(fn ->
        {data, rest} = read_stream_yield(stream)
        send(self(), {:yielded, data, rest})
      end)

    assert_received {:yielded, [], rest}
    assert_received :done
    assert log =~ "MatchError"
    assert read_stream_empty?(rest)
    assert_received :done
  end

  test "stream without awaiter is empty once nothing is left" do
    assert :no_db |> read_stream_new([]) |> read_stream_empty?()
    refute :no_db |> read_stream_new([:key]) |> read_stream_empty?()
  end
end
