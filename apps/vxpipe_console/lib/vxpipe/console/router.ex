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

  pipeline :user_pages do
    plug Vxpipe.Console.RequireUser
  end

  pipeline :user_call_access do
    plug Vxpipe.Console.AssignUserCallAccess
  end

  pipeline :diagnostics do
    plug Vxpipe.Console.DiagnosticsEnabled
  end

  pipeline :user_auth_api do
    plug :accepts, ["json"]

    plug Plug.Parsers,
      parsers: [:urlencoded, :json],
      pass: ["application/json"],
      json_decoder: Phoenix.json_library()

    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Vxpipe.Console.PrivateNoStore
  end

  pipeline :user_api do
    plug :user_auth_api
    plug Vxpipe.Console.RequireUserAPI
  end

  pipeline :session_product_api do
    plug Vxpipe.Console.SessionProductAPI
    plug :user_api
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
    pipe_through [:browser, :operator_pages, :user_pages]

    get "/pipecat-console", Vxpipe.Console.PageController, :index
    get "/transfer", Vxpipe.Console.PageController, :index
  end

  scope "/admin/samples" do
    pipe_through :user_api

    post "/calls", Vxpipe.Console.SampleCallController, :create
    post "/transfers", Vxpipe.Console.SampleTransferController, :create
  end

  scope "/" do
    pipe_through :browser

    get "/operator/sign-in", Vxpipe.Console.LegacyOperatorSessionController, :guidance
    post "/operator/session", Vxpipe.Console.LegacyOperatorSessionController, :reject
    post "/operator/sign-out", Vxpipe.Console.LegacyOperatorSessionController, :reject
  end

  scope "/" do
    pipe_through [:browser, :operator_pages]
    get "/", Vxpipe.Console.ConsoleLandingController, :index
  end

  scope "/" do
    pipe_through [:browser, :operator_pages, :user_pages]
    get "/tenants", Vxpipe.Console.CanonicalPageController, :index
    get "/tenants/new", Vxpipe.Console.CanonicalPageController, :index
    get "/getting-started", Vxpipe.Console.CanonicalPageController, :index
    get "/my-tenants", Vxpipe.Console.CanonicalPageController, :index
    get "/account", Vxpipe.Console.CanonicalPageController, :index
    get "/users", Vxpipe.Console.CanonicalPageController, :index
    get "/users/new", Vxpipe.Console.CanonicalPageController, :index
    get "/users/:id", Vxpipe.Console.CanonicalPageController, :index
    get "/users/:id/reset-password", Vxpipe.Console.CanonicalPageController, :index
    get "/roles", Vxpipe.Console.CanonicalPageController, :index
    get "/roles/new", Vxpipe.Console.CanonicalPageController, :index
    get "/roles/:id", Vxpipe.Console.CanonicalPageController, :index
    get "/api-keys", Vxpipe.Console.CanonicalPageController, :index
    get "/api-keys/new", Vxpipe.Console.CanonicalPageController, :index
    get "/platform/services", Vxpipe.Console.CanonicalPageController, :index
    get "/t/:tenant_key/dashboard", Vxpipe.Console.CanonicalPageController, :index
    get "/t/:tenant_key/calls", Vxpipe.Console.CanonicalPageController, :index
    get "/t/:tenant_key/call-specs", Vxpipe.Console.CanonicalPageController, :index
    get "/t/:tenant_key/services", Vxpipe.Console.CanonicalPageController, :index
  end

  scope "/auth" do
    pipe_through [:browser, :operator_pages]

    get "/setup", Vxpipe.Console.AdminPageController, :index
    get "/login", Vxpipe.Console.AdminPageController, :index
    get "/recover", Vxpipe.Console.AdminPageController, :index
    post "/logout", Vxpipe.Console.UserAuthController, :logout
  end

  scope "/auth/api" do
    pipe_through :user_auth_api

    get "/status", Vxpipe.Console.UserAuthController, :status
    post "/setup", Vxpipe.Console.UserAuthController, :setup
    post "/login", Vxpipe.Console.UserAuthController, :login
    post "/recover", Vxpipe.Console.UserAuthController, :recover
  end

  scope "/api" do
    pipe_through :session_product_api

    post "/tenants", Vxpipe.Console.AdminTenantsController, :create,
      metadata: %{console_product_api: true}

    get "/api-keys", Vxpipe.Console.ApiKeyController, :index,
      metadata: %{console_product_api: true}

    get "/api-keys/tenants", Vxpipe.Console.ApiKeyController, :tenants,
      metadata: %{console_product_api: true}

    post "/api-keys", Vxpipe.Console.ApiKeyController, :create,
      metadata: %{console_product_api: true}

    delete "/api-keys/:id", Vxpipe.Console.ApiKeyController, :delete,
      metadata: %{console_product_api: true}
  end

  scope "/api" do
    pipe_through :session_product_api

    post "/platform/credentials/test", Vxpipe.Console.AdminServicesController, :validate_platform,
      metadata: %{console_product_api: true}

    post "/platform/credentials", Vxpipe.Console.AdminServicesController, :create_platform,
      metadata: %{console_product_api: true}

    get "/platform/services", Vxpipe.Console.AdminServicesController, :platform_index,
      metadata: %{console_product_api: true}

    patch "/platform/credentials/:credential_id",
          Vxpipe.Console.AdminServicesController,
          :update_platform, metadata: %{console_product_api: true}

    get "/tenants/:tenant_key/telephony-services/:service/numbers",
        Vxpipe.Console.AdminPhoneNumbersController,
        :index, metadata: %{console_product_api: true}

    get "/tenants/:tenant_key/services", Vxpipe.Console.AdminServicesController, :index,
      metadata: %{console_product_api: true}

    get "/tenants/:tenant_key/telephony-applications",
        Vxpipe.Console.AdminTelephonyApplicationsController,
        :index, metadata: %{console_product_api: true}

    post "/tenants/:tenant_key/telephony-applications",
         Vxpipe.Console.AdminTelephonyApplicationsController,
         :create, metadata: %{console_product_api: true}

    patch "/tenants/:tenant_key/telephony-applications/:service_id",
          Vxpipe.Console.AdminTelephonyApplicationsController,
          :update, metadata: %{console_product_api: true}

    get "/tenants/:tenant_key/service-bindings",
        Vxpipe.Console.AdminServicesController,
        :tenant_bindings, metadata: %{console_product_api: true}

    get "/tenants/:tenant_key/credentials",
        Vxpipe.Console.AdminServicesController,
        :index_credentials, metadata: %{console_product_api: true}

    post "/tenants/:tenant_key/credentials/test",
         Vxpipe.Console.AdminServicesController,
         :validate, metadata: %{console_product_api: true}

    post "/tenants/:tenant_key/credentials", Vxpipe.Console.AdminServicesController, :create,
      metadata: %{console_product_api: true}

    delete "/tenants/:tenant_key/credentials/:credential_id",
           Vxpipe.Console.AdminServicesController,
           :delete, metadata: %{console_product_api: true}

    delete "/platform/credentials/:credential_id",
           Vxpipe.Console.AdminServicesController,
           :delete_platform, metadata: %{console_product_api: true}

    patch "/tenants/:tenant_key/credentials/:credential_id",
          Vxpipe.Console.AdminServicesController,
          :update, metadata: %{console_product_api: true}
  end

  scope "/api" do
    pipe_through :session_product_api

    post "/users/:id/reset-password", Vxpipe.Console.UserManagementController, :reset_password,
      metadata: %{console_product_api: true}

    get "/roles", Vxpipe.Console.RoleManagementController, :index,
      metadata: %{console_product_api: true}

    get "/roles/:id", Vxpipe.Console.RoleManagementController, :show,
      metadata: %{console_product_api: true}

    post "/roles", Vxpipe.Console.RoleManagementController, :create,
      metadata: %{console_product_api: true}

    patch "/roles/:id", Vxpipe.Console.RoleManagementController, :update,
      metadata: %{console_product_api: true}

    delete "/roles/:id", Vxpipe.Console.RoleManagementController, :delete,
      metadata: %{console_product_api: true}
  end

  scope "/admin/api" do
    pipe_through :session_product_api

    post "/tenants", Vxpipe.Console.AdminTenantsController, :create

    post "/users/:id/reset-password", Vxpipe.Console.UserManagementController, :reset_password
    get "/roles", Vxpipe.Console.RoleManagementController, :index
    get "/roles/:id", Vxpipe.Console.RoleManagementController, :show
    post "/roles", Vxpipe.Console.RoleManagementController, :create
    patch "/roles/:id", Vxpipe.Console.RoleManagementController, :update
    delete "/roles/:id", Vxpipe.Console.RoleManagementController, :delete
  end

  scope "/admin/api" do
    pipe_through :session_product_api

    post "/platform/credentials/test", Vxpipe.Console.AdminServicesController, :validate_platform

    post "/platform/credentials", Vxpipe.Console.AdminServicesController, :create_platform

    get "/platform/services", Vxpipe.Console.AdminServicesController, :platform_index

    patch "/platform/credentials/:credential_id",
          Vxpipe.Console.AdminServicesController,
          :update_platform

    get "/tenants/:tenant_key/telephony-services/:service/numbers",
        Vxpipe.Console.AdminPhoneNumbersController,
        :index

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

    get "/tenants/:tenant_key/credentials",
        Vxpipe.Console.AdminServicesController,
        :index_credentials

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

  scope "/admin/api" do
    pipe_through :user_api

    get "/session", Vxpipe.Console.UserSessionController, :show
    get "/navigation", Vxpipe.Console.NavigationController, :show
    get "/role-options", Vxpipe.Console.RoleManagementController, :options
    patch "/account", Vxpipe.Console.AccountController, :update
    get "/users", Vxpipe.Console.UserManagementController, :index
    get "/users/:id", Vxpipe.Console.UserManagementController, :show
    post "/users", Vxpipe.Console.UserManagementController, :create
    patch "/users/:id", Vxpipe.Console.UserManagementController, :update
  end

  scope "/admin/api" do
    pipe_through :session_product_api

    get "/api-keys", Vxpipe.Console.ApiKeyController, :index
    get "/api-keys/tenants", Vxpipe.Console.ApiKeyController, :tenants
    post "/api-keys", Vxpipe.Console.ApiKeyController, :create
    delete "/api-keys/:id", Vxpipe.Console.ApiKeyController, :delete
  end

  scope "/admin/api" do
    pipe_through :user_api

    post "/onboarding/demo-tenant", Vxpipe.Console.AdminOnboardingController, :ensure_demo_tenant

    post "/onboarding/demo-tenant/samples",
         Vxpipe.Console.AdminOnboardingController,
         :install_samples

    get "/tenants", Vxpipe.Console.AdminTenantsController, :index
    get "/tenants/:tenant_key/dashboard", Vxpipe.Console.TenantDashboardController, :show
    get "/tenants/:tenant_key/providers", Vxpipe.Console.AdminProviderCatalogController, :index

    get "/tenants/:tenant_key/providers/:provider/models",
        Vxpipe.Console.AdminProviderCatalogController,
        :models

    get "/tenants/:tenant_key/call-spec-editor-lookups",
        Vxpipe.Console.AdminCallSpecLookupsController,
        :index

    get "/tenants/:tenant_key/call-specs", Vxpipe.Console.AdminCallSpecsController, :index

    get "/tenants/:tenant_key/call-specs/:id",
        Vxpipe.Console.AdminCallSpecAuthoringController,
        :show

    post "/tenants/:tenant_key/call-specs",
         Vxpipe.Console.AdminCallSpecAuthoringController,
         :create

    put "/tenants/:tenant_key/call-specs/:id",
        Vxpipe.Console.AdminCallSpecAuthoringController,
        :update

    post "/tenants/:tenant_key/call-specs/:id/revisions/:revision/publish",
         Vxpipe.Console.AdminCallSpecAuthoringController,
         :publish

    get "/tenants/:tenant_key/calls", Vxpipe.Console.AdminCallsController, :index

    get "/tenants/:tenant_key/calls/spec-options",
        Vxpipe.Console.AdminCallsController,
        :spec_options

    get "/tenants/:tenant_key/calls/:call_id", Vxpipe.Console.AdminCallDetailsController, :show
  end

  scope "/tenants/:tenant_key/calls" do
    pipe_through [:browser, :operator_pages, :user_pages]

    get "/", Vxpipe.Console.LegacyCallRouteController, :index
    get "/:call_id", Vxpipe.Console.LegacyCallRouteController, :show
    get "/:call_id/console", Vxpipe.Console.LegacyCallRouteController, :show
  end

  scope "/tenants/:tenant_key/calls" do
    pipe_through [
      :browser,
      :operator_pages,
      :user_pages,
      :user_call_access
    ]

    get "/:call_id/details/:publication_id", Vxpipe.Console.CallDetailsController, :show
    get "/:call_id/recordings/:artifact_id", Vxpipe.Console.CallRecordingController, :show
  end

  scope "/tenants/:tenant_key/calls" do
    pipe_through [:user_api, :user_call_access]

    get "/:call_id/inspection", Vxpipe.Console.CallInspectionController, :show
  end

  scope "/admin/diagnostics" do
    pipe_through [:diagnostics, :browser, :operator_pages, :user_pages]

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
    pipe_through [:browser, :operator_pages, :user_pages]

    get "/", Vxpipe.Console.CanonicalPageController, :legacy
    get "/*path", Vxpipe.Console.CanonicalPageController, :legacy
  end
end
