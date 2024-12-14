defmodule ChatWeb.Router do
  use ChatWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ChatWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ChatWeb.Plugs.OperatingSystemDetector
    plug ChatWeb.Plugs.PreferSSL
  end

  pipeline :api do
    plug CORSPlug, origin: "*"

    plug Plug.Parsers,
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library()

    plug :accepts, ["json"]
  end

  pipeline :upload do
    plug ChatWeb.Plugs.PreferSSL
  end

  scope "/", ChatWeb do
    pipe_through :browser

    # pretty used
    get "/get/file/proxy/:server/:id", ProxiedFileController, :file
    get "/get/image/proxy/:server/:id", ProxiedFileController, :image

    get "/get/file/:id", FileController, :file
    get "/get/image/:id", FileController, :image
    get "/get/zip/:broker_key", ZipController, :get
    get "/privacy-policy.html", PlainController, :privacy_policy

    # prod debug
    # coveralls-ignore-start
    get "/log", DeviceLogController, :log
    get "/db_log/prev/prev", DeviceLogController, :db_log_prev_prev
    get "/db_log/prev", DeviceLogController, :db_log_prev
    get "/db_log", DeviceLogController, :db_log
    get "/data_keys", DeviceLogController, :dump_data_keys
    get "/get/lsmod", TempSyncController, :lsmod
    get "/get/modprobe", TempSyncController, :modprobe
    get "/reset", DeviceLogController, :reset
    # coveralls-ignore-stop

    # outdated ?
    # coveralls-ignore-start
    get "/get/backup/:key", FileController, :backup
    get "/get/backup", TempSyncController, :backup
    get "/get/device_log/:key", TempSyncController, :device_log
    # coveralls-ignore-stop

    live_session :default do
      live "/", MainLive.Index, :index
      live "/room/:hash", MainLive.Index, :room_message_link
      live "/chat/:hash", MainLive.Index, :chat_link
      live "/export-key-ring/:id", MainLive.Index, :export

      live "/proxy/:address/", ProxyLive.Index, :proxy
    end
  end

  scope "/", ChatWeb do
    pipe_through :upload

    put "/upload_chunk/:key", UploadChunkController, :put
  end

  scope "/proxy-api/", ChatWeb do
    get "/select", ProxyApiController, :select
    get "/key-value", ProxyApiController, :key_value
    get "/confirmation-token", ProxyApiController, :confirmation_token
    post "/bulk-get", ProxyApiController, :bulk_get
    post "/register-user", ProxyApiController, :register_user
    post "/create-dialog", ProxyApiController, :create_dialog
    post "/save-parcel", ProxyApiController, :save_parcel
    post "/update", ProxyApiController, :update
  end

  scope "/" do
    pipe_through :api

    forward "/naive_api", Absinthe.Plug, schema: NaiveApi.Schema
    # coveralls-ignore-next-line
    forward "/naive_api_console", Absinthe.Plug.GraphiQL, schema: NaiveApi.Schema
  end

  # Other scopes may use custom stacks.
  # scope "/api", ChatWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  #  if Mix.env() in [:dev, :test] do
  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through :browser

    # coveralls-ignore-next-line
    live_dashboard "/dashboard",
      metrics: ChatWeb.Telemetry,
      additional_pages: [
        # flame_on: FlameOn.DashboardPage
      ]
  end
end
