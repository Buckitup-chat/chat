Path.wildcard("priv/*_db/") |> Enum.each(&File.rm_rf/1)
ExUnit.start()

# :live_server tests hit a real external host (see test/live_server/) — never
# run them as part of the default suite. Opt in with `--include live_server`.
ExUnit.configure(exclude: [live_server: true])

# Start the application which includes the repo
{:ok, _} = Application.ensure_all_started(:chat)

# Start the sandbox for transaction tests - use manual mode for better async test support
Ecto.Adapters.SQL.Sandbox.mode(Chat.Repo, :manual)
