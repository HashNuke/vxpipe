defmodule Vxpipe.Console.Router do
  use Phoenix.Router

  import Phoenix.LiveDashboard.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug Plug.Parsers, parsers: [:urlencoded, :multipart], pass: ["*/*"]
    plug :fetch_session
    plug Vxpipe.Console.OperatorLoginCredentials
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :operator_pages do
    plug Vxpipe.Console.PrivateNoStore
  end

  pipeline :installation_operator do
    plug Vxpipe.Console.RequireInstallationOperator
  end

  pipeline :installation_operator_api do
    plug :accepts, ["json"]

    plug Plug.Parsers,
      parsers: [:urlencoded, :json],
      pass: ["application/json"],
      json_decoder: Phoenix.json_library()

    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Vxpipe.Console.PrivateNoStore
    plug Vxpipe.Console.RequireInstallationOperatorAPI
  end

  pipeline :diagnostics do
    plug Vxpipe.Console.DiagnosticsEnabled
  end

  pipeline :operator do
    plug Vxpipe.Console.RequireOperator
    plug Vxpipe.Console.RequireTenant
  end

  pipeline :operator_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :put_secure_browser_headers
    plug Vxpipe.Console.RequireOperator
    plug Vxpipe.Console.RequireTenant
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

    get "/", Vxpipe.Console.HomeController, :index
    get "/pipecat-console", Vxpipe.Console.PageController, :index
    get "/transfer", Vxpipe.Console.PageController, :index
    get "/operator/sign-in", Vxpipe.Console.OperatorSessionController, :new
    post "/operator/session", Vxpipe.Console.OperatorSessionController, :create
    post "/operator/sign-out", Vxpipe.Console.OperatorSessionController, :delete
  end

  scope "/auth" do
    pipe_through [:browser, :operator_pages]

    get "/login", Vxpipe.Console.OperatorLoginController, :guidance
    get "/login-token/:token", Vxpipe.Console.OperatorLoginController, :new
    post "/login-token", Vxpipe.Console.OperatorLoginController, :create
    post "/logout", Vxpipe.Console.OperatorLoginController, :delete
  end

  scope "/admin/api" do
    pipe_through :installation_operator_api

    get "/session", Vxpipe.Console.AdminSessionController, :show
    get "/tenants", Vxpipe.Console.AdminTenantsController, :index
    get "/tenants/:tenant_key/definitions", Vxpipe.Console.AdminDefinitionsController, :index
    get "/tenants/:tenant_key/calls", Vxpipe.Console.AdminCallsController, :index
  end

  scope "/admin" do
    pipe_through [:browser, :operator_pages, :installation_operator]

    get "/", Vxpipe.Console.AdminPageController, :index
    get "/*path", Vxpipe.Console.AdminPageController, :index
  end

  scope "/tenants/:tenant_key/calls" do
    pipe_through [:browser, :operator]

    get "/:call_id/console", Vxpipe.Console.CallConsolePageController, :show
    get "/:call_id/details/:publication_id", Vxpipe.Console.CallDetailsController, :show
    get "/:call_id/recordings/:artifact_id", Vxpipe.Console.CallRecordingController, :show

    live_session :vxpipe_call_inspection,
      root_layout: {Vxpipe.Console.CallInspectionLayout, :root},
      session: {Vxpipe.Console.OperatorSession, :live_session, []},
      on_mount: [Vxpipe.Console.OperatorLiveAuthentication] do
      live "/", Vxpipe.Console.CallInspectionLive, :index
      live "/:call_id", Vxpipe.Console.CallInspectionDetailLive, :show
    end
  end

  scope "/tenants/:tenant_key/calls" do
    pipe_through :operator_api

    get "/:call_id/inspection", Vxpipe.Console.CallInspectionController, :show
  end

  scope "/diagnostics" do
    pipe_through [:diagnostics, :browser]

    live_session :vxpipe_diagnostics,
      root_layout: {Vxpipe.Console.DiagnosticsLayout, :root} do
      live "/", Vxpipe.Console.DiagnosticsLive, :index
    end

    live_dashboard "/system",
      live_socket_path: "/diagnostics/live"
  end
end
