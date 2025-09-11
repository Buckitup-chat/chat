Path.wildcard("priv/*_db/") |> Enum.each(&File.rm_rf/1)
ExUnit.start()

# Start the application which includes the repo
{:ok, _} = Application.ensure_all_started(:chat)

# Start the sandbox for transaction tests - use manual mode for better async test support
Ecto.Adapters.SQL.Sandbox.mode(Chat.Repo, :manual)
