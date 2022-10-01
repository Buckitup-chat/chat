defmodule ChatWeb.Router do
  use ChatWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ChatWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ChatWeb do
    pipe_through :browser

    get "/index", PageController, :index
    get "/get/file/:id", FileController, :file
    get "/get/image/:id", FileController, :image
    get "/get/backup/:key", FileController, :backup
    get "/get/backup", TempSyncController, :backup
    get "/get/device_log/:key", TempSyncController, :device_log

    live "/", MainLive.Index, :index
    live "/export-key-ring/:id", MainLive.Index, :export
  end

  scope "/", ChatWeb do
    put "/upload_chunk/:key", UploadChunkController, :put
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

    live_dashboard "/dashboard", metrics: ChatWeb.Telemetry
  end

  #  end

  # Tell all captured traffic to try later
  scope "/", log: false do
    match(:*, "/:first", ChatWeb.UnusedTrafficController, :not_available)
    match(:*, "/:first/:sec", ChatWeb.UnusedTrafficController, :not_available)
    match(:*, "/:first/:sec/:third", ChatWeb.UnusedTrafficController, :not_available)
    match(:*, "/:first/:sec/:third/:forth", ChatWeb.UnusedTrafficController, :not_available)
  end
end
