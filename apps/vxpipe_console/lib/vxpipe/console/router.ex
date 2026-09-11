defmodule Vxpipe.Console.Router do
  use Phoenix.Router

  import Phoenix.LiveDashboard.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug Plug.Parsers, parsers: [:urlencoded, :multipart], pass: ["*/*"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :diagnostics do
    plug Vxpipe.Console.DiagnosticsEnabled
  end

  pipeline :operator do
    plug Vxpipe.Console.RequireOperator
  end

  pipeline :sample_api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
  end

  scope "/sample" do
    pipe_through :sample_api

    post "/calls", Vxpipe.Console.SampleCallController, :create
    post "/transfers", Vxpipe.Console.SampleTransferController, :create
  end

  scope "/" do
    pipe_through :browser

    get "/", Vxpipe.Console.PageController, :index
    get "/operator/sign-in", Vxpipe.Console.OperatorSessionController, :new
    post "/operator/session", Vxpipe.Console.OperatorSessionController, :create
    post "/operator/sign-out", Vxpipe.Console.OperatorSessionController, :delete
    get "/calls/assets/:kind/:hash", Vxpipe.Console.CallInspectionAssetController, :show
  end

  scope "/calls" do
    pipe_through [:browser, :operator]

    live_session :vxpipe_call_inspection,
      root_layout: {Vxpipe.Console.CallInspectionLayout, :root},
      session: {Vxpipe.Console.OperatorSession, :live_session, []},
      on_mount: [Vxpipe.Console.OperatorLiveAuthentication] do
      live "/", Vxpipe.Console.CallInspectionLive, :index
      live "/:call_id", Vxpipe.Console.CallInspectionDetailLive, :show
    end
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
