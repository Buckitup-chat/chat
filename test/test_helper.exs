Path.wildcard("priv/*_db/") |> Enum.each(&File.rm_rf/1)
ExUnit.start()
