# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the endpoint
config :chat, ChatWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: ChatWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Chat.PubSub,
  live_view: [signing_salt: "N+hZlbsm"],
  allow_reset_data: true

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :chat, Chat.Mailer, adapter: Swoosh.Adapters.Local

# Swoosh API client is needed for adapters other than SMTP.
# config :swoosh, :api_client, false

# Configure esbuild (the version is required)
# config :esbuild,
#   version: "0.24.2",
#   default: [
#     args:
#       ~w(js/app.js --bundle --target=es2022 --format=esm --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
#     cd: Path.expand("../assets", __DIR__),
#     env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
#   ]
#
# config :tailwind,
#   version: "3.0.12",
#   default: [
#     args: ~w(
#       --config=tailwind.config.js
#       --input=css/app.css
#       --output=../priv/static/assets/app.css
#     ),
#     cd: Path.expand("../assets", __DIR__)
#   ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Timezone config
config :tzdata, :autoupdate, :disabled
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :chat,
  data_pid: nil,
  files_base_dir: "priv/db/files",
  write_budget: 1_000_000,
  mode: :internal,
  flags: [],
  writable: :yes,
  env: config_env(),
  file_chunk_size: 10 * 1024 * 1024

config :chat, Chat.Db.ChangeTracker, expire_seconds: 31

config :chat,
  topic_to_platform: "chat->platform",
  topic_from_platform: "platform->chat",
  topic_to_zerotier: "-> zerotier"

# Uncomment the following line to enable db writing logging
# config :chat, :db_write_logging, true

config :mime, :types, %{
  "text/plain" => ["social_part", "data"],
  "application/zip" => ["fw"]
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
