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

  pipeline :installation_operator_call do
    plug Vxpipe.Console.AssignInstallationCallAccess
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

  scope "/admin/samples" do
    pipe_through [:browser, :operator_pages, :installation_operator]

    get "/pipecat-console", Vxpipe.Console.PageController, :index
    get "/transfer", Vxpipe.Console.PageController, :index
  end

  scope "/admin/samples" do
    pipe_through :installation_operator_api

    post "/calls", Vxpipe.Console.SampleCallController, :create
    post "/transfers", Vxpipe.Console.SampleTransferController, :create
  end

  scope "/" do
    pipe_through :browser

    get "/operator/sign-in", Vxpipe.Console.LegacyOperatorSessionController, :guidance
    post "/operator/session", Vxpipe.Console.LegacyOperatorSessionController, :reject
    post "/operator/sign-out", Vxpipe.Console.LegacyOperatorSessionController, :reject
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
    post "/platform/credentials/test", Vxpipe.Console.AdminServicesController, :validate_platform
    post "/platform/credentials", Vxpipe.Console.AdminServicesController, :create_platform
    get "/platform/services", Vxpipe.Console.AdminServicesController, :platform_index

    patch "/platform/credentials/:credential_id",
          Vxpipe.Console.AdminServicesController,
          :update_platform

    post "/onboarding/demo-tenant", Vxpipe.Console.AdminOnboardingController, :ensure_demo_tenant

    post "/onboarding/demo-tenant/samples",
         Vxpipe.Console.AdminOnboardingController,
         :install_samples

    get "/tenants", Vxpipe.Console.AdminTenantsController, :index
    get "/tenants/:tenant_key/providers", Vxpipe.Console.AdminProviderCatalogController, :index

    get "/tenants/:tenant_key/providers/:provider/models",
        Vxpipe.Console.AdminProviderCatalogController,
        :models

    get "/tenants/:tenant_key/call-specs", Vxpipe.Console.AdminCallSpecsController, :index
    get "/tenants/:tenant_key/calls", Vxpipe.Console.AdminCallsController, :index
    get "/tenants/:tenant_key/calls/:call_id", Vxpipe.Console.AdminCallDetailsController, :show
    get "/tenants/:tenant_key/services", Vxpipe.Console.AdminServicesController, :index

    get "/tenants/:tenant_key/telephony-applications",
        Vxpipe.Console.AdminTelephonyApplicationsController,
        :index

    post "/tenants/:tenant_key/telephony-applications",
         Vxpipe.Console.AdminTelephonyApplicationsController,
         :create

    patch "/tenants/:tenant_key/telephony-applications/:service_id",
          Vxpipe.Console.AdminTelephonyApplicationsController,
          :update

    get "/tenants/:tenant_key/service-bindings",
        Vxpipe.Console.AdminServicesController,
        :tenant_bindings

    post "/tenants/:tenant_key/credentials/test",
         Vxpipe.Console.AdminServicesController,
         :validate

    post "/tenants/:tenant_key/credentials", Vxpipe.Console.AdminServicesController, :create

    delete "/tenants/:tenant_key/credentials/:credential_id",
           Vxpipe.Console.AdminServicesController,
           :delete

    delete "/platform/credentials/:credential_id",
           Vxpipe.Console.AdminServicesController,
           :delete_platform

    patch "/tenants/:tenant_key/credentials/:credential_id",
          Vxpipe.Console.AdminServicesController,
          :update
  end

  scope "/tenants/:tenant_key/calls" do
    pipe_through [:browser, :operator_pages, :installation_operator]

    get "/", Vxpipe.Console.LegacyCallRouteController, :index
    get "/:call_id", Vxpipe.Console.LegacyCallRouteController, :show
    get "/:call_id/console", Vxpipe.Console.LegacyCallRouteController, :show
  end

  scope "/tenants/:tenant_key/calls" do
    pipe_through [
      :browser,
      :operator_pages,
      :installation_operator,
      :installation_operator_call
    ]

    get "/:call_id/details/:publication_id", Vxpipe.Console.CallDetailsController, :show
    get "/:call_id/recordings/:artifact_id", Vxpipe.Console.CallRecordingController, :show
  end

  scope "/tenants/:tenant_key/calls" do
    pipe_through [:installation_operator_api, :installation_operator_call]

    get "/:call_id/inspection", Vxpipe.Console.CallInspectionController, :show
  end

  scope "/admin/diagnostics" do
    pipe_through [:diagnostics, :browser, :operator_pages, :installation_operator]

    live_session :vxpipe_diagnostics,
      on_mount: Vxpipe.Console.DiagnosticsAuth,
      root_layout: {Vxpipe.Console.DiagnosticsLayout, :root} do
      live "/", Vxpipe.Console.DiagnosticsLive, :index
    end

    live_dashboard "/system",
      live_socket_path: "/admin/diagnostics/live",
      on_mount: Vxpipe.Console.DiagnosticsAuth
  end

  scope "/admin" do
    pipe_through [:browser, :operator_pages, :installation_operator]

    get "/", Vxpipe.Console.AdminPageController, :index
    get "/*path", Vxpipe.Console.AdminPageController, :index
  end
end
