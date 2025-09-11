import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :chat, ChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ABUZKxav/bWgALTw9KJRhIKc03955IEvFKODEKAl8MdscEm5iNfRO0VyM88gxe7w",
  server: false

# In test we don't send emails.
config :chat, Chat.Mailer, adapter: Swoosh.Adapters.Test

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :chat, :cub_db_file, "priv/test_db"
config :chat, :admin_cub_db_file, "priv/test_admin_db"

config :chat,
  files_base_dir: "priv/test_db/files",
  write_budget: 100_000_000,
  writable: :yes

config :chat, Chat.Db.ChangeTracker, expire_seconds: 3

# Configure your database for testing
config :chat, Chat.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "chat_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
