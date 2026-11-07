defmodule Vxpipe.Console.Test.MCPRuntimeNodeCase do
  @moduledoc false
  use ExUnit.CaseTemplate
  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Console.Test.{MCPNodeHTTP, MCPRotationRepo, MCPRuntimeNode, OutboundMCPOAuthServer}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.ConnectionStore
  alias Vxpipe.Persistence.Schema.Tenant

  using do
    quote do
      import Vxpipe.Console.Test.MCPRuntimeNodeCase
      alias Vxpipe.Console.Test.{MCPRuntimeNode, OutboundMCPOAuthServer}
      @moduletag :integration
    end
  end

  setup_all do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    :ok
  end

  setup tags do
    {repo, repository, cleanup?} = repository(tags)

    {:ok, keyring} =
      CredentialKeyring.new("node-test", %{"node-test" => :crypto.strong_rand_bytes(32)})

    context = [repo: repo, keyring: keyring]
    grant = Map.get(tags, :grant, "authorization_code")
    tenant = tenant(repo, cleanup?)
    other_tenant = tenant(repo, cleanup?)

    state =
      start_supervised!(
        {Agent,
         fn ->
           OutboundMCPOAuthServer.initial("own_client")
           |> Map.put(:hold_tokens, false)
           |> Map.put(:grant, grant)
         end}
      )

    server =
      start_supervised!(
        {Bandit, plug: {MCPNodeHTTP, %{owner: self(), state: state}}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    base = "http://127.0.0.1:#{port}"
    connection = connection(context, tenant, state, "node-client", grant)
    other = connection(context, other_tenant, state, "other-client", grant)

    nodes =
      for index <- 0..1 do
        peer =
          start_supervised!(%{
            id: {:mcp_runtime_node, index},
            start:
              {:peer, :start_link,
               [%{connection: :standard_io, args: [~c"+S", ~c"2:2", ~c"-pa" | :code.get_path()]}]},
            restart: :temporary
          })

        {peer, :peer.call(peer, MCPRuntimeNode, :boot, [repository, context, base], 30_000)}
      end

    [{first, first_identity}, {second, second_identity}] = nodes
    assert first_identity.os_pid != second_identity.os_pid
    assert first_identity.backend != second_identity.backend
    refute System.pid() in [first_identity.os_pid, second_identity.os_pid]

    %{
      context: context,
      grant: grant,
      tenant: tenant,
      other_tenant: other_tenant,
      id: connection.id,
      other_id: other.id,
      state: state,
      base: base,
      first: first,
      second: second
    }
  end

  def rpc(peer, function, args \\ []),
    do: :peer.call(peer, MCPRuntimeNode, function, args, 15_000)

  def saved(data), do: ConnectionStore.resolve(data.context, data.tenant, data.id)
  def tokens(data), do: OutboundMCPOAuthServer.count(data.state, {"POST", "/token"})
  def hold(data, value), do: Agent.update(data.state, &%{&1 | hold_tokens: value})

  def async(label, operation) do
    owner = self()

    start_supervised!(
      {Task,
       fn ->
         result =
           try do
             operation.()
           catch
             _, _ -> {:error, :node_stopped}
           end

         send(owner, {label, result})
       end},
      id: {:node_operation, label}
    )
  end

  def open(data) do
    assert :ok = rpc(data.first, :open, [data.tenant, data.id, data.base])
    assert_receive {:node_sse_stream, stream, []}, 5_000

    assert_receive {:node_mcp_request, "GET", ["Bearer node-client-access"], ["node-workspace"]},
                   5_000

    flush_protocol()
    stream
  end

  def flush_protocol do
    receive do
      {:node_mcp_request, _, _, _} -> flush_protocol()
      {:node_rpc, _} -> flush_protocol()
    after
      0 -> :ok
    end
  end

  defp repository(%{isolated_database: true}) do
    database = "vxpipe_mcp_rotation_" <> String.replace(Ecto.UUID.generate(), "-", "")

    options =
      Repo.config()
      |> Keyword.delete(:url)
      |> Keyword.put(:database, database)
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 2)

    :ok = Ecto.Adapters.Postgres.storage_up(options)
    on_exit(fn -> :ok = Ecto.Adapters.Postgres.storage_down(options) end)
    start_supervised!({MCPRotationRepo, options})
    migrations = Application.app_dir(:vxpipe_persistence, "priv/repo/migrations")
    Ecto.Migrator.run(MCPRotationRepo, migrations, :up, all: true, log: false)
    {MCPRotationRepo, options, false}
  end

  defp repository(_tags) do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    {Repo, Repo.config(), true}
  end

  defp tenant(repo, cleanup?) do
    {:ok, tenant, _} =
      Administration.bootstrap_tenant("MCP node acceptance", [:admin],
        credential_repository: {CredentialStore, repo}
      )

    if cleanup? do
      on_exit(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)
        Repo.delete_all(from(t in Tenant, where: t.key == ^tenant.key))
        Sandbox.checkin(Repo)
      end)
    end

    tenant.key
  end

  defp connection(context, tenant, state, client, grant) do
    secret = "synthetic-node-client-secret"
    refresh = client <> "-refresh"
    access = client <> "-access"

    Agent.update(state, fn s ->
      %{
        s
        | clients:
            Map.put(s.clients, client, %{
              "token_endpoint_auth_method" => "client_secret_basic",
              "client_secret" => secret
            }),
          refresh:
            if(grant == "authorization_code",
              do: Map.put(s.refresh, refresh, client),
              else: s.refresh
            ),
          access: MapSet.put(s.access, access)
      }
    end)

    {:ok, connection} =
      ConnectionStore.create_oauth(
        context,
        tenant,
        Ecto.UUID.generate(),
        %{
          endpoint: OutboundMCPOAuthServer.resource(),
          endpoint_identity: OutboundMCPOAuthServer.resource(),
          server_name: "Node tools",
          auth_method: "oauth",
          catalog: []
        },
        %{
          "registration_method" => "own_client",
          "grant_type" => grant,
          "auth_method" => "client_secret_basic",
          "client_id" => client,
          "client_secret" => secret,
          "token_endpoint" => OutboundMCPOAuthServer.issuer() <> "/token",
          "issuer" => OutboundMCPOAuthServer.issuer(),
          "resource" => OutboundMCPOAuthServer.resource(),
          "access_token" => access,
          "expires_at" => DateTime.utc_now() |> DateTime.add(300) |> DateTime.to_iso8601(),
          "headers" => [%{"name" => "X-Workspace", "value" => "node-workspace"}]
        }
        |> grant_configuration(grant, refresh)
      )

    connection
  end

  defp grant_configuration(secrets, "authorization_code", refresh),
    do: Map.put(secrets, "refresh_token", refresh)

  defp grant_configuration(secrets, "client_credentials", _refresh) do
    Map.merge(secrets, %{
      "scopes" => ["tools:read"],
      "machine_metadata" => %{
        "issuer" => OutboundMCPOAuthServer.issuer(),
        "token_endpoint" => OutboundMCPOAuthServer.issuer() <> "/token",
        "grant_types_supported" => ["client_credentials"],
        "token_endpoint_auth_methods_supported" => ["client_secret_basic"]
      }
    })
  end
end
