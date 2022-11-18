defmodule Chat.DbPoc do
  def run(stream_count, path \\ nil) do
    path =
      if path do
        path
      else
        [System.tmp_dir!(), "db_poc"]
        |> Path.join()
      end

    db =
      path
      |> tap(&File.mkdir_p!/1)
      |> CubDB.start_link(auto_compact: false)
      |> elem(1)
      |> tap(&CubDB.clear/1)

    IO.puts("pepared")

    time = System.system_time(:second) + 10

    1..stream_count
    |> Task.async_stream(
      fn index ->
        write_random_till(index, db, time)
      end,
      timeout: 60_000
    )
    |> Stream.run()

    size = CubDB.size(db)

    CubDB.stop(db)

    size
  end

  defp write_random_till(index, db, till) do
    1..10
    |> Enum.each(fn data ->
      CubDB.put(db, {:data, index, :rand.uniform(1_000_000_000_000_000)}, data)
    end)

    if System.system_time(:second) < till do
      write_random_till(index, db, till)
    end
  end
end
