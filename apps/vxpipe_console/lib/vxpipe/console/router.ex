defmodule Vxpipe.Console.Router do
  use Phoenix.Router

  import Phoenix.LiveDashboard.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :diagnostics do
    plug Vxpipe.Console.DiagnosticsEnabled
  end

  pipeline :sample_api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
  end

  scope "/sample" do
    pipe_through :sample_api

    post "/calls", Vxpipe.Console.SampleCallController, :create
  end

  scope "/" do
    pipe_through :browser

    get "/", Vxpipe.Console.PageController, :index
  end

  scope "/diagnostics" do
    pipe_through [:diagnostics, :browser]

    get "/assets/live/:hash", Vxpipe.Console.DiagnosticsAssetController, :show

    live_session :vxpipe_diagnostics,
      root_layout: {Vxpipe.Console.DiagnosticsLayout, :root} do
      live "/", Vxpipe.Console.DiagnosticsLive, :index
    end

    live_dashboard "/system",
      live_socket_path: "/diagnostics/live"
  end
end
