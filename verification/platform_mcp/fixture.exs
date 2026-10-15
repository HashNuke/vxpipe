defmodule Vxpipe.PlatformMCPFixture do
  @moduledoc false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.ApiKeyManagement
  alias Vxpipe.Console.Endpoint, as: ConsoleEndpoint
  alias Vxpipe.Gateway.HTTP.{Endpoint, Mount}
  alias Vxpipe.Identity.{Bootstrap, Sessions}
  alias Vxpipe.Persistence.{CredentialKeyring, IdentityInstallationStore, Repo}

  @password "synthetic-sdk-bootstrap-password!"

  def run([port, ttl]) do
    Logger.configure(level: :critical)
    Process.put(:acceptance_stage, "configure")
    options = configure()
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

      Process.put(:acceptance_stage, "listeners")

      children = [
        listener(:gateway, {Endpoint, options}, String.to_integer(port)),
        listener(:embedded, {Mount, Keyword.put(options, :path_prefix, "/embedded")}, 0),
        listener(:console, ConsoleEndpoint, 0)
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

      # This private pipe is consumed by the runner, never printed in its output.
      reply(%{addresses: addresses, keys: keys, tenant: tenant.key, foreign: foreign.key})
      Process.put(:acceptance_stage, "commands")
      commands(actor, tenant.key)
      Supervisor.stop(supervisor)
    after
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end
  rescue
    _error -> fail()
  catch
    _kind, _reason -> fail()
  end

  defp configure do
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
    Application.put_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
    Application.put_env(:vxpipe_console, :sample_call, enabled: false)
    endpoint = Application.fetch_env!(:vxpipe_console, ConsoleEndpoint)
    Application.put_env(:vxpipe_console, ConsoleEndpoint, Keyword.put(endpoint, :server, false))

    options = [
      mcp: [enabled: true, allowed_hosts: ["127.0.0.1"], allow_loopback_http: true],
      call_admission: [enabled: true],
      account_management: [enabled: true],
      tenant_directory: [enabled: true],
      call_spec_reads: [enabled: true],
      call_spec_authoring: [enabled: true],
      room_creation: [enabled: false],
      telephony: [enabled: false]
    ]

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

  defp commands(actor, tenant) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      line when is_binary(line) ->
        line |> JSON.decode!() |> command(actor, tenant) |> reply()
        commands(actor, tenant)
    end
  end

  defp command(%{"action" => "issue_revocable"}, actor, tenant) do
    {:ok, issued} = ApiKeyManagement.create(actor, "SDK revocation", "calls", tenant)
    %{id: issued.key.id, secret: issued.secret}
  end

  defp command(%{"action" => "revoke", "id" => id}, actor, _tenant) do
    :ok = ApiKeyManagement.revoke(actor, id)
    %{ok: true}
  end

  defp command(%{"action" => "session_exists", "session" => session}, _actor, _tenant),
    do: %{exists: match?({:ok, _}, ExMCP.SessionManager.get_session(session))}

  defp command(%{"action" => "await_expiry", "session" => session}, _actor, _tenant),
    do: await_expiry(session, System.monotonic_time(:millisecond) + 5_000)

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
