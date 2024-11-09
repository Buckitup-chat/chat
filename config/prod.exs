import Config

# For production, don't forget to configure the url host
# to something meaningful, Phoenix uses this information
# when generating URLs.
#
# Note we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the `mix phx.digest` task,
# which you should run after static files are built and
# before starting your production server.

hostname =
  cond do
    domain = System.get_env("DOMAIN") -> domain
    app_name = System.get_env("APP_NAME") -> "#{app_name}.gigalixirapp.com"
    true -> "demo.buckitup.org"
  end

domain_to_file_prefix = fn domain ->
  String.replace(domain, ".", "_")
end

cert_deploy_dir = cert_src_dir = Path.expand("../../cert/#{hostname}", __DIR__)
# cert_src_dir = "../cert/#{hostname}"
# cert_deploy_dir = "../chat/priv/certs"
# File.rm_rf!(cert_deploy_dir)

ssl_cacertfile = "#{domain_to_file_prefix.(hostname)}.ca-bundle"
ssl_certfile = "#{domain_to_file_prefix.(hostname)}.crt"
ssl_keyfile = "priv.key"

cert_present? =
  [ssl_cacertfile, ssl_certfile, ssl_keyfile]
  |> Enum.map(&Path.join([cert_src_dir, &1]))
  |> Enum.all?(&File.exists?/1)

if cert_present? do
  File.mkdir_p!(cert_deploy_dir)

  # [ssl_cacertfile, ssl_certfile, ssl_keyfile]
  # |> Enum.map(fn filename ->
  #   File.cp!(Path.join([cert_src_dir, filename]), Path.join([cert_deploy_dir, filename]))
  # end)

  config :chat, ChatWeb.Endpoint,
    url: [host: hostname],
    http: [ip: {0, 0, 0, 0}, port: 80],
    https: [
      port: 443,
      cipher_suite: :strong,
      cacertfile: [cert_deploy_dir, ssl_cacertfile] |> Path.join(),
      certfile: [cert_deploy_dir, ssl_certfile] |> Path.join(),
      keyfile: [cert_deploy_dir, ssl_keyfile] |> Path.join()
    ],
    secret_key_base:
      Map.get(
        System.get_env(),
        "SECRET_KEY_BASE",
        "IGuZPUcM7Vuq1iPemg6pc7EMwLLmMiVA4stbfDstZPshJ8QDqxBBcVqNnQI6clxi"
      ),
    force_ssl: [hsts: true],
    check_origin: ["//#{hostname}"],
    allow_reset_data: false,
    server: true
else
  config :chat, ChatWeb.Endpoint,
    cache_static_manifest: "priv/static/cache_manifest.json",
    # Possibly not needed, but doesn't hurt
    http: [port: System.get_env("PORT")],
    url: [host: hostname, port: 443],
    secret_key_base:
      Map.get(
        System.get_env(),
        "SECRET_KEY_BASE",
        "BKyA6n6KrL/mmKlyg5a+4/ZlWq0cN3dFqfvNj9zaw6Acvnp++u6bXN5rkns5xVpE"
      ),
    check_origin: [
      "https://offline-chat.gigalixirapp.com",
      "https://buckitup.app",
      "//#{hostname}"
    ],
    allow_reset_data: false,
    server: true
end

# url: [host: "buckitup.app", port: 443],
# secret_key_base: Map.fetch!(System.get_env(), "SECRET_KEY_BASE"),
# check_origin: ["https://buckitup.app"],
# server: true,
# https: [
#  port: 443,
#  cipher_suite: :strong,
#  cacertfile: "priv/cert/buckitup_app.ca-bundle",
#  certfile: "priv/cert/buckitup_app.crt",
#  keyfile: "priv/cert/priv.key"
# ],
# force_ssl: [hsts: true]

# Do not print debug messages in production
config :logger, level: :info

# ## SSL Support
#
# To get SSL working, you will need to add the `https` key
# to the previous section and set your `:url` port to 443:
#
#     config :chat, ChatWeb.Endpoint,
#       ...,
#       url: [host: "example.com", port: 443],
#       https: [
#         ...,
#         port: 443,
#         cipher_suite: :strong,
#         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
#         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
#       ]
#
# The `cipher_suite` is set to `:strong` to support only the
# latest and more secure SSL ciphers. This means old browsers
# and clients may not be supported. You can set it to
# `:compatible` for wider support.
#
# `:keyfile` and `:certfile` expect an absolute path to the key
# and cert in disk or a relative path inside priv, for example
# "priv/ssl/server.key". For all supported SSL configuration
# options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
#
# We also recommend setting `force_ssl` in your endpoint, ensuring
# no data is ever sent via http, always redirecting to https:
#
#     config :chat, ChatWeb.Endpoint,
#       force_ssl: [hsts: true]
#
# Check `Plug.SSL` for all available options in `force_ssl`.
