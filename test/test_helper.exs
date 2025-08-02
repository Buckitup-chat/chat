Path.wildcard("priv/*_db/") |> Enum.each(&File.rm_rf/1)
ExUnit.start()

# Start the sandbox for transaction tests
Ecto.Adapters.SQL.Sandbox.mode(Chat.Repo, :manual)
