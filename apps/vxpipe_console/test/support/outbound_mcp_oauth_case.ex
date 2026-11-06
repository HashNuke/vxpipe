defmodule Vxpipe.Console.Test.OutboundMCPOAuthCase do
  use ExUnit.CaseTemplate
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3, get_resp_header: 2]
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Console.Test.{FakeUserIdentity, OutboundMCPOAuthServer}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{ConnectionStore, OAuthAttemptStore, OAuthGrantStore}
  alias Vxpipe.Persistence.Schema.MCPOAuthAttempt
  @endpoint Vxpipe.Console.Endpoint

  using do
    quote do
      import Phoenix.ConnTest
      import Vxpipe.Console.Test.OutboundMCPOAuthCase
      alias Vxpipe.Console.Test.OutboundMCPOAuthServer
      alias Vxpipe.Persistence.Repo
      alias Vxpipe.Persistence.MCP.ConnectionStore
      alias Vxpipe.Persistence.Schema.{MCPConnection, MCPOAuthAttempt}
      @moduletag :integration
    end
  end

  setup_all do
    keys =
      for _ <- 1..2 do
        rsa = :public_key.generate_key({:rsa, 2048, 65_537})
        pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, rsa)])
        {:ok, key} = ExMCP.Authorization.JWT.load_key(pem)
        %{pem: pem, public: ExMCP.Authorization.JWT.to_public_key(key)}
      end

    %{keys: keys}
  end

  setup tags do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]
    mode = Map.get(tags, :mode, "dcr")
    peer = start_supervised!({Agent, fn -> OutboundMCPOAuthServer.initial(mode) end})

    server =
      start_supervised!(
        {Bandit, plug: {OutboundMCPOAuthServer, peer}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    grant = Map.get(tags, :grant, "authorization_code")
    OutboundMCPOAuthServer.configure(peer, %{base: "http://127.0.0.1:#{port}", grant: grant})
    tasks = start_supervised!({Task.Supervisor, name: nil})

    runner =
      start_supervised!(
        {Vxpipe.MCP.PreflightRunner, name: nil, task_supervisor: tasks, interval: 0}
      )

    protocol = Keyword.put(OutboundMCPOAuthServer.options(peer), :preflight_runner, runner)

    options = [
      credential_repository: {CredentialStore, Repo},
      mcp_connection_repository: {ConnectionStore, context},
      mcp_oauth_attempt_repository: {OAuthAttemptStore, context},
      mcp_oauth_grant_repository: {OAuthGrantStore, context},
      mcp_preflight: {Vxpipe.Console.MCPPreflight, protocol},
      mcp_connection_probe: {Vxpipe.Console.MCPConnectionProbe, protocol},
      mcp_oauth_preparation: {Vxpipe.Console.MCPOAuthPreparation, protocol},
      mcp_oauth_completion: {Vxpipe.Console.MCPOAuthCompletion, protocol}
    ]

    {:ok, tenant, _} = Administration.bootstrap_tenant("OAuth acceptance", [:admin], options)
    identity = Application.get_env(:vxpipe_console, :user_identity_backend)
    calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)
    Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.merge(calls, options))

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :user_identity_backend, identity)
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, calls)
    end)

    page =
      build_conn()
      |> post("https://localhost/auth/api/login", %{
        email: FakeUserIdentity.email(),
        password: FakeUserIdentity.password()
      })
      |> recycle()
      |> get("https://localhost/account")

    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    %{
      tenant: tenant.key,
      context: context,
      peer: peer,
      protocol: protocol,
      options: options,
      mode: mode,
      grant: grant,
      client_auth_method: tags[:client_auth_method],
      page: page,
      csrf: csrf
    }
  end

  def start(data, id \\ nil, credentials \\ nil, generation \\ 1) do
    input = %{
      "endpoint" => OutboundMCPOAuthServer.resource(),
      "revision" => "draft",
      "auth_method" => data.mode,
      "return_to" => return_to(data)
    }

    input = if credentials, do: Map.put(input, "credentials", credentials), else: input

    {path, input} =
      if id,
        do: {"/mcp-connections/#{id}/oauth", Map.put(input, "generation", generation)},
        else: {"/mcp-oauth", input}

    request(data, :post, path, input) |> json_response(201)
  end

  def register_own(data, version) do
    credentials = %{
      "grant_type" => data.grant,
      "client_id" => "registered-client",
      "client_auth_method" => data.client_auth_method,
      "audience" => "calendar-api",
      "authorization_parameters" => [%{"name" => "organization", "value" => "calendar"}],
      "token_parameters" => [%{"name" => "organization", "value" => "calendar"}],
      "headers" => [%{"name" => "X-Workspace", "value" => "workspace-#{version}"}]
    }

    registered = %{"token_endpoint_auth_method" => data.client_auth_method}

    credentials =
      if data.grant == "client_credentials",
        do: Map.delete(credentials, "authorization_parameters"),
        else: credentials

    {credentials, registered} =
      case data.client_auth_method do
        "none" ->
          {credentials, registered}

        "private_key_jwt" ->
          key = Enum.at(data.keys, version)

          {Map.merge(credentials, %{
             "private_key" => key.pem,
             "algorithm" => "RS256",
             "key_id" => "key-#{version}"
           }), Map.put(registered, "public_key", key.public)}

        _ ->
          secret = "registered-secret-#{version}"

          {Map.put(credentials, "client_secret", secret),
           Map.put(registered, "client_secret", secret)}
      end

    OutboundMCPOAuthServer.configure(data.peer, %{
      clients: %{"registered-client" => registered},
      authorization_parameters: %{"organization" => "calendar", "audience" => "calendar-api"},
      token_parameters: %{"organization" => "calendar", "audience" => "calendar-api"},
      mcp_headers: [{"x-workspace", "workspace-#{version}"}]
    })

    credentials
  end

  def request(data, method, suffix, input) do
    conn = data.page |> recycle() |> put_req_header("x-csrf-token", data.csrf)
    conn = %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}

    dispatch(
      conn,
      @endpoint,
      method,
      "https://localhost/api/tenants/#{data.tenant}" <> suffix,
      input
    )
  end

  def authorize(data, handoff) do
    response = OutboundMCPOAuthServer.authorize(data.peer, handoff["authorization_url"])
    assert response.status == 303
    [location] = Req.Response.get_header(response, "location")
    location
  end

  def callback(data, location) do
    uri = URI.parse(location)
    data.page |> recycle() |> get("https://localhost" <> uri.path <> "?" <> uri.query)
  end

  def assert_connected(data, location) do
    response = callback(data, location)
    state = URI.decode_query(URI.parse(location).query)["state"]
    attempt = Repo.get_by!(MCPOAuthAttempt, state_digest: :crypto.hash(:sha256, state))
    assert_returned(data, response, "connected", attempt.public_id)
  end

  def assert_returned(data, response, status, attempt_id) do
    assert response.status == 303, response.resp_body

    assert get_resp_header(response, "location") == [
             return_to(data) <> "&mcp=#{status}&mcp_attempt=#{attempt_id}"
           ]

    assert get_resp_header(response, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(response, "cache-control") == ["private, no-store"]
  end

  def return_to(data), do: "/t/#{data.tenant}/services/search?q=calendar"
  def count(data, key), do: OutboundMCPOAuthServer.count(data.peer, key)

  def resolve(data, id) do
    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, id)
    resolved
  end
end
