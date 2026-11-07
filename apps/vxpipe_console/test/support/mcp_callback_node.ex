defmodule Vxpipe.Console.Test.MCPCallbackNode do
  @moduledoc "Console endpoint fixture with real durable identity in an independent BEAM."
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
  alias Vxpipe.Console.{Endpoint, UserIdentity, UserSession}
  alias Vxpipe.Console.Test.OutboundMCPOAuthServer
  alias Vxpipe.Persistence.{CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{ConnectionStore, OAuthAttemptStore, OAuthGrantStore}
  alias Vxpipe.Persistence.Schema.MCPOAuthAttempt
  alias Vxpipe.Persistence.Test.MCPDatabaseNode
  @endpoint Endpoint
  @email "node-owner@example.test"
  @password "synthetic callback password 42!"

  def boot(configuration, migrate?) do
    identity = MCPDatabaseNode.boot(configuration.repository)
    Logger.configure(level: :warning)
    if migrate?, do: Ecto.Migrator.run(Repo, :up, all: true, log: false, migration_lock: false)

    Application.put_all_env(phoenix: configuration.phoenix)

    for app <- [:phoenix, :phoenix_live_view, :argon2_elixir, :req, :vxpipe_mcp] do
      {:ok, _} = Application.ensure_all_started(app)
    end

    Application.put_env(:vxpipe_identity, :dependencies, %{
      users: Vxpipe.Persistence.IdentityUserStore,
      roles: Vxpipe.Persistence.IdentityRoleStore,
      sessions: Vxpipe.Persistence.IdentitySessionStore,
      installations: Vxpipe.Persistence.IdentityInstallationStore,
      audit: Vxpipe.Persistence.IdentityAuditStore,
      attempts: Vxpipe.Persistence.IdentityAttemptStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    })

    {:ok, state} =
      Supervisor.start_child(
        MCPDatabaseNode.Supervisor,
        {Agent, fn -> %{base: configuration.base} end}
      )

    protocol = OutboundMCPOAuthServer.options(state)

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      credential_repository: {CredentialStore, Repo},
      mcp_connection_repository: {ConnectionStore, configuration.context},
      mcp_oauth_attempt_repository: {OAuthAttemptStore, configuration.context},
      mcp_oauth_grant_repository: {OAuthGrantStore, configuration.context},
      mcp_oauth_preparation: {Vxpipe.Console.MCPOAuthPreparation, protocol},
      mcp_oauth_completion: {Vxpipe.Console.MCPOAuthCompletion, protocol},
      mcp_oauth_refresh: {Vxpipe.Console.MCPOAuthRefresh, protocol}
    )

    Application.put_env(:vxpipe_console, :user_identity_backend, UserIdentity)

    Application.put_env(
      :vxpipe_console,
      Endpoint,
      configuration.endpoint
      |> Keyword.put(:server, false)
      |> Keyword.put(:gateway_mount, Vxpipe.Gateway.HTTP.Mount.init([]))
    )

    {:ok, _} =
      Supervisor.start_child(
        MCPDatabaseNode.Supervisor,
        {Phoenix.PubSub, name: Vxpipe.Console.PubSub}
      )

    {:ok, _} = Supervisor.start_child(MCPDatabaseNode.Supervisor, Endpoint)
    identity
  end

  def setup_installation do
    {:ok, _} =
      UserIdentity.setup(
        @email,
        @password,
        @password,
        nil,
        "local",
        OutboundMCPOAuthServer.origin()
      )

    {:ok, tenant, _} = Vxpipe.Calls.Administration.bootstrap_tenant("Callback nodes", [:admin])
    tenant.key
  end

  def login(email \\ @email) do
    page =
      build_conn()
      |> post("https://localhost/auth/api/login", %{email: email, password: @password})
      |> recycle()
      |> get("https://localhost/account")

    200 = page.status
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)
    %{page: page, csrf: csrf}
  end

  def start(session, tenant, mode),
    do: session |> start_response(tenant, mode) |> json_response(201)

  def start_response(session, tenant, mode) do
    conn = session.page |> recycle() |> put_req_header("x-csrf-token", session.csrf)
    conn = %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}

    conn
    |> post("https://localhost/api/tenants/#{tenant}/mcp-oauth", %{
      "endpoint" => OutboundMCPOAuthServer.resource(),
      "revision" => "node-draft",
      "auth_method" => mode,
      "return_to" => "/t/#{tenant}/services/search?q=calendar"
    })
  end

  def callback(session, location) do
    uri = URI.parse(location)
    session.page |> recycle() |> get("https://localhost" <> uri.path <> "?" <> uri.query)
  end

  def logout(session), do: UserIdentity.logout(UserSession.token(session.page))

  def refresh(tenant, id), do: Vxpipe.Calls.MCPOAuthRefresh.refresh(tenant, id, 1, 1)

  def create_writer(session, tenant) do
    {:ok, principal} = UserIdentity.authenticate(UserSession.token(session.page))

    {:ok, role} =
      UserIdentity.create_role(principal, %{
        name: "MCP writer",
        slug: "mcp-writer",
        grants: [
          %{permission: "tenant_services.read", scope: :assigned_tenants},
          %{permission: "tenant_services.write", scope: :assigned_tenants}
        ]
      })

    {:ok, _} =
      UserIdentity.create_user(principal, %{
        email: "node-writer@example.test",
        password: @password,
        password_confirmation: @password,
        role_public_id: role.public_id,
        memberships: %{tenant => "read_write"}
      })

    role
  end

  def remove_write_permission(session, role) do
    {:ok, principal} = UserIdentity.authenticate(UserSession.token(session.page))

    {:ok, _} =
      UserIdentity.update_role(principal, role.public_id, %{
        name: role.name,
        expected_revision: role.revision,
        grants: [%{permission: "tenant_services.read", scope: :assigned_tenants}]
      })

    :ok
  end

  def change_installation(session) do
    {:ok, principal} = UserIdentity.authenticate(UserSession.token(session.page))
    {:ok, installation} = UserIdentity.mcp_oauth_installation()

    {:ok, _} =
      UserIdentity.update_installation(
        principal,
        "https://new-console.example.test",
        installation.revision
      )

    :ok
  end

  def resolve(tenant, id) do
    {ConnectionStore, context} =
      Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
      |> Keyword.fetch!(:mcp_connection_repository)

    {:ok, saved} = ConnectionStore.resolve(context, tenant, id)
    saved
  end

  def connection_count(tenant) do
    {ConnectionStore, context} =
      Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
      |> Keyword.fetch!(:mcp_connection_repository)

    {:ok, connections} = ConnectionStore.list(context, tenant)
    length(connections)
  end

  def attempt_consumed?(id) do
    attempt = Repo.get_by!(MCPOAuthAttempt, public_id: id)
    not is_nil(attempt.claimed_at) and is_nil(attempt.encrypted_payload)
  end
end
