defmodule Vxpipe.PlatformMCPFixture do
  @moduledoc false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.ApiKeyManagement
  alias Vxpipe.Console.Endpoint, as: ConsoleEndpoint
  alias Vxpipe.Gateway.HTTP.{Endpoint, Mount}
  alias Vxpipe.Identity.{Accounts, Bootstrap, Roles, Sessions}
  alias Vxpipe.Persistence.OAuth.Store
  alias Vxpipe.Persistence.{CredentialKeyring, IdentityInstallationStore, Repo}

  @password "synthetic-sdk-bootstrap-password!"

  def run([port, ttl]) do
    Logger.configure(level: :critical)
    Process.put(:acceptance_stage, "configure")
    ports = reserve_ports(String.to_integer(port))
    options = configure(ports.console)
    Process.put(:acceptance_stage, "applications")
    {:ok, _started} = Application.ensure_all_started(:vxpipe_console)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true, ownership_timeout: 600_000)

    try do
      configure_expiry(String.to_integer(ttl))
      Process.put(:acceptance_stage, "bootstrap")
      actor = bootstrap()
      Process.put(:acceptance_stage, "tenants")
      {:ok, tenant, _unused} = Calls.bootstrap_tenant("Acceptance tenant", [:calls])
      {:ok, foreign, _unused} = Calls.bootstrap_tenant("Foreign acceptance tenant", [:calls])
      Process.put(:acceptance_stage, "keys")

      keys =
        for kind <- ["calls", "full", "platform"], into: %{} do
          scope = if kind == "platform", do: nil, else: tenant.key
          {:ok, key} = ApiKeyManagement.create(actor, "SDK " <> kind, kind, scope)
          {kind, key.secret}
        end

      {:ok, other} = ApiKeyManagement.create(actor, "SDK other", "platform", nil)
      keys = Map.put(keys, "other", other.secret)

      actors = %{
        "platform" => actor,
        "other" => actor,
        "calls" => scoped_actor(actor, tenant.key, "calls"),
        "full" => scoped_actor(actor, tenant.key, "full")
      }

      Process.put(:acceptance_stage, "listeners")

      children = [
        listener(
          :gateway,
          {Endpoint, oauth_options(options, ports.gateway, "/mcp")},
          ports.gateway
        ),
        listener(
          :embedded,
          {Mount,
           options
           |> oauth_options(ports.embedded, "/embedded/mcp")
           |> Keyword.put(:path_prefix, "/embedded")},
          ports.embedded
        ),
        listener(:console, ConsoleEndpoint, ports.console)
      ]

      {:ok, supervisor} =
        Supervisor.start_link(children,
          strategy: :one_for_one,
          name: Vxpipe.PlatformMCPFixture.Supervisor
        )

      addresses =
        for {id, pid, _, _} <- Supervisor.which_children(supervisor), into: %{} do
          {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
          suffix = if id == :embedded, do: "/embedded/mcp", else: "/mcp"
          {id, "http://127.0.0.1:#{port}#{suffix}"}
        end

      credentials =
        for {mount, resource} <- addresses, into: %{} do
          {mount, Map.new(actors, fn {kind, principal} -> {kind, issue(principal, resource)} end)}
        end

      # This private pipe is consumed by the runner, never printed in its output.
      reply(%{
        addresses: addresses,
        keys: keys,
        credentials: credentials,
        browser_login: %{email: "sdk-root@example.test", password: @password},
        tenant: tenant.key,
        foreign: foreign.key
      })

      Process.put(:acceptance_stage, "commands")
      commands(%{actors: actors, addresses: addresses})
      Supervisor.stop(supervisor)
    after
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end
  rescue
    _error -> fail()
  catch
    _kind, _reason -> fail()
  end

  defp configure(console_port) do
    Application.put_env(:vxpipe_persistence, :enabled, true)
    Application.put_env(:vxpipe_persistence, :call_details_publication_recovery, enabled: false)

    {:ok, keyring} =
      CredentialKeyring.new("acceptance", %{"acceptance" => :crypto.strong_rand_bytes(32)})

    original = Application.fetch_env!(:vxpipe_calls, Calls)

    Application.put_env(
      :vxpipe_calls,
      Calls,
      Keyword.merge(original,
        credential_repository: {Vxpipe.Persistence.CredentialStore, Repo},
        access_key_repository: {Vxpipe.Persistence.AccessKeyStore, Repo},
        admin_repository: {Vxpipe.Persistence.AdminStore, Repo},
        call_spec_repository: {Vxpipe.Persistence.CallSpecStore, Repo},
        call_repository: {Vxpipe.Persistence.CallStore, Repo},
        provider_credential_repository:
          {Vxpipe.Persistence.ProviderCredentialStore, [repo: Repo, keyring: keyring]},
        registries: %{host_tools: %{}}
      )
    )

    Application.put_env(:vxpipe_identity, :dependencies, dependencies())
    Application.put_env(:vxpipe_identity, :oauth_store, Store)
    Application.put_env(:vxpipe_identity, :oauth_browser_store, Vxpipe.Persistence.OAuth.Browser)
    Application.put_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
    Application.put_env(:vxpipe_console, :sample_call, enabled: false)
    endpoint = Application.fetch_env!(:vxpipe_console, ConsoleEndpoint)
    Application.put_env(:vxpipe_console, ConsoleEndpoint, Keyword.put(endpoint, :server, false))

    options =
      [
        mcp: [enabled: true, allowed_hosts: ["127.0.0.1"], allow_loopback_http: true],
        call_admission: [enabled: true],
        account_management: [enabled: true],
        tenant_directory: [enabled: true],
        call_spec_reads: [enabled: true],
        call_spec_authoring: [enabled: true],
        room_creation: [enabled: false],
        telephony: [enabled: false]
      ]
      |> oauth_options(console_port, "/mcp")

    Application.put_env(:vxpipe_console, :oauth, Keyword.fetch!(options, :oauth))
    settings = Application.fetch_env!(:vxpipe_gateway, Vxpipe.Gateway.Application)

    Application.put_env(
      :vxpipe_gateway,
      Vxpipe.Gateway.Application,
      settings
      |> Keyword.put(:http, Keyword.put(options, :enabled, false))
      |> Keyword.put(:managed_cleanup, enabled: false)
    )

    options
  end

  defp bootstrap do
    deps = dependencies()

    result =
      case Bootstrap.status(deps) do
        {:ok, :pending_first_run} ->
          Bootstrap.complete_first_run(deps, "sdk-root@example.test", @password, @password)

        {:ok, :pending_operator_proof} ->
          {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)

          Bootstrap.complete_with_proof(
            deps,
            proof,
            "sdk-root@example.test",
            @password,
            @password
          )

        _configured ->
          fail()
      end

    {:ok, %{user: root}} = result
    {:ok, %{token: token}} = Sessions.login(deps, root.email, @password, "local")
    {:ok, actor} = Sessions.authenticate(deps, token)
    actor
  end

  defp dependencies do
    %{
      users: Vxpipe.Persistence.IdentityUserStore,
      roles: Vxpipe.Persistence.IdentityRoleStore,
      sessions: Vxpipe.Persistence.IdentitySessionStore,
      installations: IdentityInstallationStore,
      audit: Vxpipe.Persistence.IdentityAuditStore,
      attempts: Vxpipe.Persistence.IdentityAttemptStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }
  end

  defp configure_expiry(ttl) do
    :ok = Supervisor.terminate_child(ExMCP.Supervisor, ExMCP.SessionManager)
    :ok = Supervisor.delete_child(ExMCP.Supervisor, ExMCP.SessionManager)

    {:ok, _} =
      Supervisor.start_child(
        ExMCP.Supervisor,
        {ExMCP.SessionManager, session_ttl_seconds: ttl, cleanup_interval_ms: 25}
      )
  end

  defp listener(id, plug, port),
    do:
      Supervisor.child_spec(
        {Bandit, plug: plug, ip: {127, 0, 0, 1}, port: port, startup_log: false},
        id: id
      )

  defp commands(context) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      line when is_binary(line) ->
        line |> JSON.decode!() |> command(context) |> reply()
        commands(context)
    end
  end

  defp command(%{"action" => "issue_revocable", "resource" => resource}, context) do
    true = resource in Map.values(context.addresses)
    issue(context.actors["calls"], resource)
  end

  defp command(%{"action" => "authorize", "params" => params, "resource" => resource}, context) do
    true = resource in Map.values(context.addresses)
    principal = context.actors["platform"]
    {:ok, snapshot} = Store.consent_snapshot(principal)
    {:ok, response} = Store.issue_code(principal, params, resource, snapshot)
    response
  end

  defp command(%{"action" => "session_exists", "session" => session}, _context),
    do: %{exists: match?({:ok, _}, ExMCP.SessionManager.get_session(session))}

  defp command(%{"action" => "await_expiry", "session" => session}, _context),
    do: await_expiry(session, System.monotonic_time(:millisecond) + 5_000)

  defp scoped_actor(actor, tenant, kind) do
    permissions =
      ~w(calls.read calls.write) ++
        if(kind == "full", do: ~w(call_specs.read call_specs.write), else: [])

    {:ok, role} =
      Roles.create_role(dependencies(), actor, %{
        name: "SDK " <> kind,
        slug: "sdk-" <> kind,
        grants: Enum.map(permissions, &%{permission: &1, scope: :assigned_tenants})
      })

    {:ok, user} =
      Accounts.create_user(dependencies(), actor, %{
        email: "sdk-" <> kind <> "@example.test",
        password: @password,
        password_confirmation: @password,
        role_public_id: role.public_id,
        memberships: %{tenant => :read_write}
      })

    {:ok, %{token: token}} = Sessions.login(dependencies(), user.email, @password, "local")
    {:ok, principal} = Sessions.authenticate(dependencies(), token)
    principal
  end

  defp issue(principal, resource) do
    {:ok, client} =
      Store.register_client(%{
        "client_name" => "SDK acceptance",
        "redirect_uris" => ["http://127.0.0.1:43210/callback"]
      })

    verifier = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    params = %{
      "response_type" => "code",
      "client_id" => client.client_id,
      "redirect_uri" => "http://127.0.0.1:43210/callback",
      "resource" => resource,
      "scope" => "mcp",
      "code_challenge_method" => "S256",
      "code_challenge" => :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    }

    {:ok, snapshot} = Store.consent_snapshot(principal)
    {:ok, issued} = Store.issue_code(principal, params, resource, snapshot)

    {:ok, tokens} =
      Store.exchange(
        %{
          "grant_type" => "authorization_code",
          "client_id" => client.client_id,
          "redirect_uri" => params["redirect_uri"],
          "resource" => resource,
          "code" => issued.code,
          "code_verifier" => verifier
        },
        resource
      )

    Map.merge(tokens, %{client_id: client.client_id, grant_id: issued.grant_id})
  end

  defp oauth_options(options, port, path) do
    issuer = "http://127.0.0.1:#{port}"

    oauth = [
      enabled: true,
      allowed_hosts: ["127.0.0.1"],
      allow_loopback_http: true,
      issuer: issuer,
      resource: issuer <> path
    ]

    options |> Keyword.put(:oauth, oauth) |> Keyword.put(:mcp, oauth)
  end

  defp reserve_ports(gateway_port) do
    sockets =
      for {name, port} <- [gateway: gateway_port, embedded: 0, console: 0] do
        {:ok, socket} =
          :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

        {:ok, {_address, allocated}} = :inet.sockname(socket)
        {name, socket, allocated}
      end

    for {_name, socket, _port} <- sockets, do: :gen_tcp.close(socket)
    Map.new(sockets, fn {name, _socket, port} -> {name, port} end)
  end

  defp await_expiry(session, deadline) do
    case ExMCP.SessionManager.get_session(session) do
      {:ok, %{status: :terminated}} ->
        %{expired: true}

      _active ->
        if System.monotonic_time(:millisecond) >= deadline, do: fail()

        receive do
        after
          25 -> await_expiry(session, deadline)
        end
    end
  end

  defp reply(value), do: IO.puts("PLATFORM_MCP " <> JSON.encode!(value))

  defp fail do
    IO.puts(:stderr, "PLATFORM_MCP_FAILURE " <> Process.get(:acceptance_stage, "startup"))
    System.halt(1)
  end
end

Vxpipe.PlatformMCPFixture.run(System.argv())
