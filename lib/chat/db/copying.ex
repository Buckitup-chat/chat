defmodule Chat.Db.Copying do
  @moduledoc """
  Manages difference copying between DBs with WriteQeue streams
  """

  import Chat.Db.WriteQueue.ReadStream
  alias Chat.Db.Common
  alias Chat.Db.WriteQueue

  def stream(from, to, awaiter \\ nil) do
    [from, to]
    |> Enum.map(fn db ->
      Task.async(fn ->
        db
        |> CubDB.select()
        |> Stream.map(fn {k, _v} -> k end)
        |> MapSet.new()
      end)
    end)
    |> Task.await_many(:timer.hours(2))
    |> then(fn [src, dst] ->
      keys =
        src
        |> MapSet.difference(dst)
        |> MapSet.to_list()

      read_stream(keys: keys, db: from, awaiter: awaiter)
    end)
  end

  def await_copied(from, to) do
    to_pipe = Common.names(to)

    awaiter =
      Task.async(fn ->
        receive do
          any -> any
        end
      end)

    stream(from, to, awaiter.pid)
    |> WriteQueue.put_stream(to_pipe.queue)

    Task.await(awaiter, :infinity)
  end
end
