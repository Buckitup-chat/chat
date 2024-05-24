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

    get "/log", DeviceLogController, :log
    get "/db_log/prev/prev", DeviceLogController, :db_log_prev_prev
    get "/db_log/prev", DeviceLogController, :db_log_prev
    get "/db_log", DeviceLogController, :db_log
    get "/reset", DeviceLogController, :reset
    get "/data_keys", DeviceLogController, :dump_data_keys
    get "/get/file/:id", FileController, :file
    get "/get/image/:id", FileController, :image
    get "/get/backup/:key", FileController, :backup
    get "/get/backup", TempSyncController, :backup
    get "/get/lsmod", TempSyncController, :lsmod
    get "/get/modprobe", TempSyncController, :modprobe
    get "/get/device_log/:key", TempSyncController, :device_log
    get "/get/zip/:broker_key", ZipController, :get
    get "/privacy-policy.html", PlainController, :privacy_policy

    live_session :default do
      live "/", MainLive.Index, :index
      live "/export-key-ring/:id", MainLive.Index, :export
      live "/room/:hash", MainLive.Index, :room_message_link
      live "/chat/:hash", MainLive.Index, :chat_link
    end
  end

  scope "/", ChatWeb do
    pipe_through :upload

    put "/upload_chunk/:key", UploadChunkController, :put
  end

  scope "/" do
    pipe_through :api

    forward "/naive_api", Absinthe.Plug, schema: NaiveApi.Schema
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

    live_dashboard "/dashboard",
      metrics: ChatWeb.Telemetry,
      additional_pages: [
        # flame_on: FlameOn.DashboardPage
      ]
  end
end
